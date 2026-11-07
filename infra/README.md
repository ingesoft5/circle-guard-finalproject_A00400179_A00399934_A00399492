# Infraestructura de CircleGuard en AWS (HU-01)

Scripts Bash idempotentes y stacks Docker Compose que aprovisionan, configuran, verifican y
destruyen la plataforma de HU-01:

- **Herramientas (topología B):** dos instancias EC2 `m7i-flex.large`.
  - El servidor `ci` ejecuta Jenkins (JCasC) y SonarQube (con PostgreSQL).
  - El servidor `nexus` ejecuta el **registro Docker principal**, CNCF Distribution
    (`REGISTRY_BACKEND=distribution`, decisión del equipo): TLS, usuario `ci` y volumen
    persistente, sin EULA. Nexus Repository sigue instalado, con el EULA sin aceptar, y nada
    depende de él. Decisión y trade-offs en
    [registro-artefactos.md](../docs/arquitectura/registro-artefactos.md).
  - Jenkins publica y descarga imágenes en el registro con `crane`, sin el socket de Docker
    ([Integración de Jenkins con el registro](#integración-de-jenkins-con-el-registro)).
  - **Verificado en AWS el 2026-11-03** con `test-idempotency.sh`: publicación y descarga desde `ci` y
    desde Jenkins ([evidencias](../docs/evidencias/hu-01/aws/idempotencia/README.md)).
- **Ambientes `dev`, `stage` y `prod`:** cada uno tiene subred, grupo de seguridad, credenciales,
  llave SSH y **servidor propio** (`t3.small`). El límite de vCPU que fija el equipo
  (`QUOTA_VCPU_LIMIT=5`, por presupuesto; la cuota real es de 16) solo permite dos servidores
  encendidos a la vez, así que se crean y se prueban **por pares**.
  - **Verificado en AWS el 2026-11-03/04** con `test-isolation.sh`: tráfico entre ambientes
    bloqueado e idempotencia de `bootstrap-env.sh`
    ([evidencias](../docs/evidencias/hu-01/aws/aislamiento/README.md)).
  - Detalle en [Ambientes dev, stage y prod](#ambientes-dev-stage-y-prod-servidores-por-pares).

Arquitectura y reglas de red: [docs/arquitectura/infra-ambientes.md](../docs/arquitectura/infra-ambientes.md).
Evidencias de HU-01: [docs/evidencias/hu-01/](../docs/evidencias/hu-01/README.md). Despliegue en AWS
del 2026-11-02 (Jenkins, SonarQube y PostgreSQL validados; Nexus sin EULA aceptado; instancias
detenidas después): [evidencia 14](../docs/evidencias/hu-01/14-despliegue-aws-fase4.md).

> **Costos.** Crear o iniciar instancias consume créditos de AWS. Ningún script crea recursos
> facturables sin `--apply --approve <rol>`. El modo por defecto, `--plan`, no cambia nada.
> Detenga las instancias al terminar cada sesión (`bash infra/teardown.sh --stop --apply`).

---

## Contenido

| Ruta | Función |
|---|---|
| `bootstrap-all.sh` | **Comando único**: red → secretos → servidores → Jenkins y SonarQube (en `ci`) → Nexus y registro (en `nexus`) → hosts de ambiente (si los hay) → verificación |
| `bootstrap-network.sh` | VPC, 4 subredes públicas, internet gateway (sin NAT Gateway), tabla de rutas y grupos de seguridad de mínimo privilegio |
| `bootstrap-secrets.sh` | Secretos del catálogo en SSM Parameter Store (SecureString) y llaves SSH por nivel |
| `bootstrap-servers.sh` | Instancias EC2 (FACTURABLE: requiere `--approve`); `--prices` consulta precios vigentes |
| `bootstrap-jenkins.sh`, `bootstrap-sonarqube.sh`, `bootstrap-nexus.sh` | Preparan el host, despliegan el stack y configuran la herramienta por código o API |
| `bootstrap-registry.sh` | Registro Docker CNCF Distribution en el servidor `nexus` (TLS y usuario `ci` generados en el host); con `REGISTRY_BACKEND=nexus` lo retira conservando su volumen |
| `bootstrap-env.sh <env>` | Prepara un host de `dev`, `stage` o `prod` (Docker, Compose, parada automática y `.env` propio). Solo actúa si el ambiente figura en `ENV_SERVERS` y su instancia está en ejecución |
| `verify-infra.sh` | Verificación: servidores, salud, EULA de Nexus, registro, aislamiento, credenciales, prueba de publicación (`--registry`) y *snapshot* (`PASS`, `FAIL` o `PENDING`) |
| `test-idempotency.sh` | Prueba de idempotencia integral en AWS: dos `bootstrap-all.sh`, *snapshots*, comparaciones, persistencia, registro desde el host y desde Jenkins, recuperación tras reiniciar los contenedores y parada obligatoria (FACTURABLE: requiere `--apply --approve`) |
| `test-isolation.sh` | Prueba de aislamiento de dev, stage y prod con tráfico, por pares de servidores dentro de la cuota, con parada entre fases y al final (FACTURABLE: requiere `--apply`) |
| `rotate-registry-password.sh` | Rotación de la contraseña del usuario `ci` del registro: SSM, registro y Jenkins, con comprobación y recuperación |
| `check-prerequisites.sh` | Comprobación de solo lectura de la estación de trabajo (herramientas, plataforma, repositorio, finales de línea y configuración), sin AWS. Primer paso del ensayo de reconstrucción |
| `tunnel.sh <herramienta>` | Acceso administrativo a Jenkins, SonarQube o Nexus por **túnel SSH** (las UIs nunca se exponen a Internet) |
| `teardown.sh` | Detiene (`--stop`) o elimina (`--destroy`) **solo** los recursos de HU-01 |
| `scan-secrets.sh` | Escaneo de secretos con Gitleaks (árbol de trabajo e historial) |
| `check-evidence.sh <carpeta>` | Comprobación de solo lectura, sin AWS, de una carpeta de evidencias antes de versionarla: número de cuenta, IP públicas, claves, secretos y rutas personales (solo cuenta, no muestra nada) |
| `aws-session.sh` | Sesiones AWS temporales: abre la página oficial de AWS (`aws login`); estado y cierre de sesión |
| `bootstrap-iam.sh` | Inspección de solo lectura de la cuenta, validación con Access Analyzer y creación de los roles y usuarios de HU-01 (con aprobación) |
| `config/aws.env` | Configuración **no secreta**: región, CIDR, tipos, puertos, precios de referencia |
| `config/envs/<env>.env` | Subred, tipo y disco de cada ambiente |
| `config/secrets.catalog` | **Nombres** y generadores de los secretos (nunca valores) |
| `config/iam/hu01-{reader,operator,teardown}-policy.json` | Permisos de los tres roles: lectura y detener; crear e iniciar sin borrar; destruir solo lo etiquetado |
| `config/iam/hu01-*-role-trust.json`, `hu01-*-user-policy.json` | Quién asume cada rol y con qué MFA; permisos mínimos de los dos usuarios (sin claves) |
| `bootstrap/lib/*.sh` | Librerías: utilidades comunes, AWS, sesiones, estimación de costos y transporte SSH/local |
| `bootstrap/host/setup-docker.sh` | Se ejecuta en el host: Docker Engine, Compose, rotación de logs, `vm.max_map_count`, swap de seguridad y parada automática |
| `bootstrap/{jenkins,sonarqube,nexus,registry}/` | Stacks Compose con imágenes fijadas y scripts de configuración por API (`registry/prepare.sh` genera el certificado y el usuario antes de arrancar el contenedor) |

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
   - acepta solo la AMI fijada en `AMI_ID` (Ubuntu 24.04 de Canonical, condición `ec2:ImageID`) y
     secretos bajo `/circleguard/*`;
   - **no incluye ninguna acción destructiva.**

   Destruir solo es posible con el rol de teardown, que asume **otro usuario**
   ([`hu01-teardown-policy.json`](config/iam/hu01-teardown-policy.json)).
4. **Docker Desktop** con integración WSL, solo para la validación local y para Gitleaks.
5. Los scripts se ejecutan desde la raíz del repositorio con `bash infra/<script>.sh`. Para
   operar AWS desde WSL, clone el repositorio en el sistema de archivos de WSL (`~/…`): sobre una
   carpeta de Windows o de OneDrive (`/mnt/c/…`), `git status` puede tardar decenas de minutos
   (medido el 2026-11-03: 26 min).
6. Compruebe la estación de trabajo con `bash infra/check-prerequisites.sh` (solo lectura, sin AWS):
   debe terminar con `fail=0`.

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
| Rol `circleguard-hu01-teardown` | **Usuario de teardown** + código MFA de menos de 15 min | Describir (política de lectura adjunta) y borrar solo recursos con `Project=circleguard` | MFA obligatorio; sesiones de 1 h como máximo |

Los usuarios IAM `circleguard-hu01-operator` y `circleguard-hu01-teardown` no tienen claves ni
permisos propios: solo pueden usar `aws login`, ver su propio dispositivo MFA y asumir sus roles.

### Autorización técnica

1. **Capacidades separadas en AWS.** La lectura no crea ni borra; el operador no borra; destruir
   solo es posible con el rol de teardown, que únicamente asume el otro usuario.
2. **La persona abre la ventana con su MFA.** El rol de operación exige una MFA de menos de 1 h
   (`aws:MultiFactorAuthAge < 3600`).
   - **Comprobado el 2026-11-01:** cuando el usuario operador inicia sesión con `aws login` y
     escribe su MFA en la página de AWS, la sesión transmite el contexto MFA. Con la raíz sin
     MFA, no lo transmitía (`mfaAuthenticated=false`).
   - Por eso el rol de operación está disponible durante la hora siguiente a cada inicio de
     sesión del operador, sin otro código. Pasada esa hora, AWS lo rechaza hasta un nuevo inicio
     de sesión o un `unlock`, que envía un código MFA nuevo en `AssumeRole`.
   - **Destrucción:** solo desde **AWS CloudShell**, en el navegador, con la sesión del usuario de
     teardown (contraseña y MFA en la página de AWS). Ninguna credencial de teardown llega a esta
     máquina.
3. **Límites de lo que se puede crear** (política del operador): `us-east-2`, `t3.small`,
   `c7i-flex.large` y `m7i-flex.large`, gp3 cifrado de 40 GiB como máximo, solo la AMI fijada en
   `AMI_ID` y etiqueta `Project=circleguard` obligatoria. Cambiar de AMI exige actualizar a la vez
   `AMI_ID` (`config/aws.env`) y la sentencia `RunOnlyPinnedUbuntuImage`, y aplicar IAM.
4. **Barreras de los scripts**, como defensa adicional: `--plan` por defecto, `--apply --approve
   <rol>` para lo facturable, frase para destruir y estimación local de costos.
5. **Auditoría:** CloudTrail registra cada llamada con su identidad y si tenía MFA.

**Estado de la política `circleguard-hu01-teardown`.** En AWS, la versión predeterminada es la
**v2**, creada desde la consola el 2026-11-02 durante el diagnóstico de CloudShell: añade la
declaración `PreflightZoneCheck` (`ec2:DescribeAvailabilityZones` en `us-east-2`), que es
redundante porque el rol ya la tiene por la política `circleguard-hu01-reader` adjunta. Se decidió
conservarla: desde el commit `b18f27c` la plantilla del repositorio es idéntica a la v2 (orden de
las sentencias incluido), así que `bootstrap-iam.sh` la muestra UNCHANGED y un `--apply` no la
cambia (ver la [evidencia 12](../docs/evidencias/hu-01/12-preparacion-arquitectura-b.txt) y la
sección 9 del [documento 13](../docs/evidencias/hu-01/13-plan-despliegue-fase3.txt)).

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
bash infra/aws-session.sh open root-mfa          # antes de nada: MFA de la cuenta raíz (la activa usted en la consola)
bash infra/aws-session.sh init                   # ~/.circleguard/aws (0700) y perfiles de inicio de sesión
bash infra/aws-session.sh login bootstrap        # se abre el navegador: inicie sesión con su identidad actual
bash infra/bootstrap-iam.sh                      # solo lectura: cuenta, permisos, cuotas, Access Analyzer y plan
bash infra/bootstrap-iam.sh --audit              # CloudTrail: contexto MFA y escrituras desde el inicio de sesión
bash infra/bootstrap-iam.sh --apply --approve iam   # CON APROBACIÓN: crea roles y usuarios (sin costo)
bash infra/bootstrap-quota.sh                    # cuota de vCPU frente a QUOTA_VCPU_TARGET (10); solo lectura
bash infra/bootstrap-quota.sh --apply --approve quota  # CON APROBACIÓN, solo si la cuota fuera menor que QUOTA_VCPU_TARGET (sin costo)
bash infra/aws-session.sh logout bootstrap       # la identidad administrativa deja de estar disponible
```

**Primer acceso de los usuarios** (una vez, en la consola de AWS, con la identidad actual).
`bash infra/aws-session.sh open operator` (y después `open teardown`) abre IAM → Usuarios →
`circleguard-hu01-operator` → Credenciales de seguridad:
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

- `config/aws.env`: región `us-east-2`, zona `us-east-2a`, CIDR `10.20.0.0/16`, servidores
  (`CI_*` y `NEXUS_*`: `m7i-flex.large`, 30 y 25 GiB), puertos, parada automática
  (`AUTO_STOP_HOURS`), swap (`SWAP_GB`), precios de referencia, presupuesto estimado
  (`HU01_BUDGET_USD`), vCPU necesarias con todo encendido (`QUOTA_VCPU_TARGET=10`) y límite de
  vCPU encendidas a la vez (`QUOTA_VCPU_LIMIT=5`).
  La cuenta está en el **plan gratuito de AWS**, que solo lanza tipos aptos para la capa gratuita
  (8 GiB como máximo). Memoria por servidor:
  - `ci`: Jenkins (recomendación oficial para un equipo pequeño: 4 GB) y SonarQube (instalación
    pequeña: 4 GB y 2 núcleos) con PostgreSQL, ambos con los valores por defecto de sus JVM.
  - `nexus`: Sonatype exige un host de 8 GB y un *heap* mínimo de 2703 MB, con *heap* + memoria
    directa ≤ 2/3 de la RAM. `-Xms2703m -Xmx2703m -XX:MaxDirectMemorySize=2703m` suma 5406 MiB,
    dentro de los 5461 MiB (2/3 de 8192 MiB). No se reduce.
  - CPU: los 4 vCPU de Sonatype son una **recomendación** de su perfil de referencia más pequeño
    (100 peticiones por segundo sostenidas), no un mínimo. Con 2 vCPU, los arranques y las tareas
    largas son más lentos; Community Edition admite como máximo 100 000 peticiones al día.
- `config/envs/{dev,stage,prod}.env`: subredes `10.20.{10,20,30}.0/24`. El tipo y el disco solo se
  usan para los ambientes que figuren en `ENV_SERVERS`.
- `REGISTRY_BACKEND` (en `aws.env`): `distribution` (por defecto) despliega CNCF Distribution en el
  8082 del servidor `nexus` y deja el conector de Nexus, sin uso, en `127.0.0.1:18082`
  (`NEXUS_DOCKER_STANDBY_PORT`). `nexus` devuelve el 8082 al repositorio `circleguard-docker`, y
  solo sirve con el EULA aceptado. Cambiar de opción no migra imágenes.
- `ENV_SERVERS` (en `aws.env`): ambientes con servidor, `dev,stage,prod` (decisión del
  2026-11-03); vacío equivale a solo aislamiento por red.
- `QUOTA_VCPU_LIMIT` (en `aws.env`): límite conservador de vCPU encendidas a la vez, **5**, por
  decisión del equipo. **No es la cuota de la cuenta**: `bootstrap-quota.sh` leyó 16 vCPU el
  2026-11-03 (el valor por defecto de AWS es 5;
  [evidencia](../docs/evidencias/hu-01/auditoria/20261103T201403Z-bootstrap-quota.txt)).
  - `bootstrap-servers.sh` se niega a crear o iniciar servidores que lo superen. Solo cuenta los
    servidores de CircleGuard (2 vCPU cada uno).
  - Subirlo hasta `QUOTA_VCPU_TARGET=10` permitiría encender los cinco a la vez. Nunca debe superar
    la cuota real.
- `config/operator.local.env` (ignorado): `ADMIN_CIDRS` (y, si hace falta, `CG_AWS_PROFILE`). Si `ADMIN_CIDRS` está
  vacío, se usa la IP pública actual del operador (`/32`).
- `NEXUS_ACCEPT_EULA=false` (en `aws.env`): **decisión definitiva del equipo, no se acepta el EULA**
  de Nexus Community Edition 3.96.5 (<https://links.sonatype.com/products/nxrm/ce-eula>).
  - El bootstrap despliega Nexus y aplica la contraseña gestionada. No crea el repositorio
    `circleguard-docker` ni cambia el acceso anónimo o los *realms*.
  - Nexus queda instalado **sin función de registro**. El registro de imágenes es CNCF
    Distribution (`REGISTRY_BACKEND=distribution`).
  - `configure.sh` informa ese estado como `UNCHANGED` y `verify-infra.sh` como `PASS`.

## Gestión de secretos

| Ámbito | Ruta en SSM (SecureString) | Contenido |
|---|---|---|
| Herramientas | `/circleguard/tools/{jenkins,sonarqube,nexus,registry}/*` | Contraseñas de administrador, de la BD de SonarQube y del usuario `ci` del registro (32 valores del catálogo en total, más las 4 llaves) |
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
| 4. Servidores | `bash infra/bootstrap-servers.sh --apply --approve ci,nexus` (o uno solo) | **Sí**: EC2, EBS e IPv4 pública |
| 5. Herramientas | `bash infra/bootstrap-{jenkins,sonarqube,nexus,registry}.sh --apply` (en ese orden) | Horas de instancia |
| 6. Ambientes | Por pares: `bootstrap-servers.sh --apply --approve env-dev,env-stage` y `bootstrap-env.sh dev --apply` (y `stage`), o todo con `test-isolation.sh --apply` | **Sí** (`t3.small`) |
| 7. Verificación | `bash infra/verify-infra.sh` | Horas de instancia |
| 8. Acceso administrativo | `bash infra/tunnel.sh jenkins` (o `sonarqube`, `nexus`) y abrir `http://localhost:8080` | Horas de instancia |

**Comando único** (reconstrucción desde cero, después de aprobar el costo):
```bash
bash infra/bootstrap-all.sh --plan                          # recorrido completo sin cambios + costo estimado
bash infra/bootstrap-all.sh --apply --approve ci,nexus      # FACTURABLE: Jenkins, SonarQube y registro
```
- **Qué construye o converge:** red, secretos, servidores, Jenkins, SonarQube, Nexus y el registro.
- **Ambientes:** sus servidores se encienden por pares, porque el límite configurado
  (`QUOTA_VCPU_LIMIT=5`) no admite los cinco a la vez. Por eso `--approve all` se rechaza antes de
  llamar a AWS mientras el límite sea de 5 vCPU.
- **Un solo servidor:** con `--approve ci`, los pasos del servidor `nexus` se omiten.

**Parada automática.** Cada servidor se apaga solo (`shutdown --poweroff`) `AUTO_STOP_HOURS` (4)
horas después de arrancar: la instancia queda **detenida**, con su disco EBS conservado, nunca
terminada. Al volver a iniciarla, Docker debería levantar los stacks solos (`restart: unless-stopped`
y volúmenes con nombre sobre el EBS). Esa recuperación tras un arranque **aún no se ha comprobado en
AWS** ([evidencia 14](../docs/evidencias/hu-01/14-despliegue-aws-fase4.md), §9). En el host:

| Situación | Comando |
|---|---|
| Ver cuánto falta | `systemctl list-timers circleguard-autostop.timer` |
| Alargar la sesión antes del aviso | `sudo systemctl restart circleguard-autostop.timer` (otras `AUTO_STOP_HOURS` horas desde ahora) |
| Seguir trabajando durante el aviso de 5 minutos | `sudo shutdown -c && sudo systemctl restart circleguard-autostop.timer` |

`sudo shutdown -c` **por sí solo** cancela el apagado pero deja el servidor **sin ninguna parada
programada** hasta el siguiente arranque: el temporizador ya venció. La siguiente ejecución de
los *bootstrap* lo detecta y lo reprograma, y `verify-infra.sh --health` falla mientras no esté
en espera. La estimación local registra estas paradas con la hora que da AWS, o con una hora
estimada (y un aviso) si AWS no la indica.

### Presupuesto por recurso (topología B en el plan gratuito, On-Demand en us-east-2)

Tarifas de la AWS Pricing API del 2026-11-02. Son **estimaciones**, no costos garantizados:
confírmelas antes de cada sesión con `bash infra/bootstrap-servers.sh --prices` (solo lectura).
En el plan gratuito todo se descuenta de los créditos y AWS no cobra más allá de ellos (el plan
termina el 2027-04-30 03:45 UTC o al agotarse los créditos), pero **el límite de HU-01 es de 15
USD** y los créditos no se consideran presupuesto disponible.

| Recurso | Cantidad | Tarifa | Encendido (USD/h) | Detenido | USD/día (24 h encendido) | USD/mes (730 h) |
|---|---|---|---|---|---|---|
| EC2 `ci` `m7i-flex.large` (2 vCPU, 8 GiB): Jenkins, SonarQube y PostgreSQL | 1 | 0.09576/h | 0.0958 | 0 | 2.30 | 69.90 |
| EC2 `nexus` `m7i-flex.large` (2 vCPU, 8 GiB) | 1 | 0.09576/h | 0.0958 | 0 | 2.30 | 69.90 |
| IPv4 pública (automática, sin Elastic IP) | 2 | 0.005/h c/u | 0.0100 | 0 (se libera) | 0.24 | 7.30 |
| EBS gp3 cifrado (30 + 25 GiB) | 55 GiB | 0.08/GB-mes | 0.0060 | **0.0060/h** | 0.145 | 4.40 |
| Transferencia de salida a Internet | reserva de 3 GB | 0.09/GB (la entrada no se cobra) | — | — | — | 0.27 en total |
| SSM Parameter Store estándar y KMS `aws/ssm` | 35 parámetros | Sin cargo (capa gratuita de KMS) | 0 | 0 | 0 | 0 |
| VPC, subredes, IGW, rutas, grupos de seguridad, pares de llaves, IAM, CloudShell, Service Quotas | — | Sin cargo | 0 | 0 | 0 | 0 |
| NAT Gateway, balanceadores, Elastic IP, *snapshots*, servidores de ambiente | — | **No se usan** | 0 | 0 | 0 | 0 |
| **Total** | | | **0.2075** | **0.145 USD/día** | **4.98** | **151.5** |

**Encendida 24/7, la plataforma consumiría los 15 USD en unos 3 días.** Por eso se trabaja por
sesiones y cada servidor se apaga solo a las 4 horas: una sesión olvidada cuesta como máximo
0.81 USD (las dos instancias durante 4 h).

### Ejecución por sesiones (estimación para completar HU-01)

Cada sesión empieza con la autorización de las operaciones facturables que contiene y termina con
`bash infra/teardown.sh --stop --apply`. Con `ci` y `nexus` encendidas se cobran 0.2015 USD/h
(EC2 e IPv4), más el EBS, que se cobra mientras los volúmenes existen. Las dos instancias suman
4 vCPU: caben en el límite configurado de 5 (y en la cuota real de 16).

| Sesión | Contenido | Operaciones facturables que se autorizan | Duración | Costo | Acumulado |
|---|---|---|---|---|---|
| Preparación | Fases 0 a 2: inspección, diseño y preparación local | Ninguna | — | 0 | 0 |
| S1 | Red, secretos y llaves (sin cargo); crear `ci` y `nexus`; Jenkins, SonarQube y Nexus (EULA no aceptado); 2.ª ejecución; `verify-infra.sh` | `run-instances` ci y nexus | 3 h | 0.60 | 0.60 |
| S2 | Evidencias y ensayo: `verify-infra.sh` completo, *snapshot*, túneles | `start-instances` ×2 | 3 h | 0.60 | 1.21 |
| S3 | Demostración académica | `start-instances` ×2 | 2.5 h | 0.50 | 1.71 |
| — | Holgura | — | 0.5 h | 0.10 | 1.81 |
| — | Contingencia (se duplican las horas: depuración y reintentos) | Según la sesión | 9 h | 1.81 | 3.63 |
| — | EBS de 55 GiB mientras existen los volúmenes | — | 45 días | 6.51 | 10.14 |
| — | Reserva de transferencia de salida | — | 3 GB | 0.27 | **10.41** |
| **Total HU-01** | | | | **≈ 10.4 USD con margen**; sin margen (9 h, 30 días, 1 GB) ≈ 6.2 USD (límite: 15 USD) | |

El EBS es el costo dominante: se cobra desde que se crea cada volumen hasta que se destruye (`ci`
0.079 y `nexus` 0.066 USD/día), con las instancias encendidas o detenidas. Con el margen de horas,
los 15 USD alcanzan para unos 2.5 meses de volúmenes: al terminar la evaluación hay que destruir
la infraestructura (en CloudShell, con su propia autorización).

**Otros costos:**
- **Transferencia:** la entrada (imágenes, paquetes, plugins) no se cobra. La salida a Internet
  cuesta 0.09 USD/GB (Pricing API); se reservan 3 GB aunque el uso esperado (túneles SSH) es muy
  inferior, y no se cuenta con los 100 GB gratuitos. El tráfico entre `ci` y `nexus` usa IP
  privadas en la misma zona, que no se cobra.
- **Servicios auxiliares:** SSM estándar, KMS `aws/ssm` dentro de la capa gratuita, STS, Access
  Analyzer, Pricing API y la monitorización básica de CloudWatch no tienen cargo. No se usan
  *snapshots*, NAT, Elastic IP ni balanceadores.

**Barreras de costo:**
- **Parada automática** de cada servidor a las `AUTO_STOP_HOURS` (4) horas del arranque; la
  instancia se detiene y conserva el disco. `verify-infra.sh` comprueba que hay una parada
  programada (temporizador en espera, no solo «activo»).
- **Estimación local** antes de crear o iniciar: acumulado + sesión (4 h; 24 h y un aviso si la
  parada automática está desactivada) + EBS nuevo (45 días) + reserva de transferencia, frente a
  15 USD.
- **AWS Budgets** (requiere aprobación): alertas en 5, 10 y 15 USD. Solo avisan, con horas de
  retraso: no detienen nada. Según la API del plan gratuito, crear un presupuesto de costos es una
  actividad que suma 20 USD de créditos (igual que lanzar la primera instancia EC2).
- Al cerrar cada sesión, ejecute `teardown.sh --stop --apply` y confirme que no queda nada encendido:
  ```bash
  aws ec2 describe-instances --region us-east-2 \
    --filters Name=tag:Project,Values=circleguard Name=instance-state-name,Values=running \
    --query 'Reservations[].Instances[].InstanceId'
  ```
- **Línea operativa de parada: 12 USD** (80 % del presupuesto absoluto de **15 USD**). No se inicia
  ninguna sesión si el costo real (consola de Billing) más la sesión prevista (0.81 USD con ambas
  durante 4 h) supera 12 USD: se detiene todo y se revisa con el equipo. La estimación local no es la
  factura, y los créditos no eliminan el riesgo de costo.
- Al finalizar la evaluación, destruya la infraestructura desde CloudShell (ver «Detener o
  destruir»), como pide el enunciado.
- **Fuera de HU-01:** desplegar las aplicaciones en los ambientes (E1.5) necesitará servidores más
  grandes y subir `QUOTA_VCPU_LIMIT` (la cuota real de 16 vCPU lo admite), y aumentará el costo por
  hora.
- **Rendimiento:** cada servidor tiene 2 vCPU (por debajo de los 4 vCPU del perfil de referencia
  más pequeño de Sonatype, que es una recomendación). El primer arranque de SonarQube o Nexus puede
  tardar de 5 a 10 minutos; los scripts esperan y se pueden reejecutar sin riesgo.

## Idempotencia: cómo demostrarla

Prueba automatizada (FACTURABLE: inicia los servidores unos 40 minutos y **siempre** los detiene
al final, también si algo falla):
```bash
bash infra/aws-session.sh login operator                    # la ventana del rol de operación dura 1 h
bash infra/test-idempotency.sh                              # --plan: describe los pasos, sin AWS
bash infra/test-idempotency.sh --apply --approve ci,nexus   # pide escribir 'PROBAR IDEMPOTENCIA'
```
Hace S0 → `bootstrap-all.sh` → S1 → `bootstrap-all.sh` → S2 → `verify-infra.sh --registry` y deja
en `~/.circleguard/idempotency/<marca UTC>/` los *snapshots*, las salidas, los `diff`,
`report.txt` y `masked/` (copias sin número de cuenta, IP públicas ni hashes de archivos
secretos, listas para las evidencias). Criterios:

| Comprobación | Esperado |
|---|---|
| `diff S1 S2` | Vacío |
| `SUMMARY` de la 2.ª ejecución | `created=0 updated=0` y ninguna línea `CREATED` ni `UPDATED` |
| Persistencia en la 1.ª ejecución | Contraseñas gestionadas todavía válidas; el contenedor de Jenkins es anterior a la prueba |
| `S0 → S1` | Sin cambios en la red ni en las llaves (salvo la regla del 22 si cambió la IP del operador) |

El *snapshot* lista:
- VPC, subredes, rutas, reglas de seguridad y llaves;
- nombres y versiones de los parámetros SSM, sin valores;
- instancias;
- hashes de los archivos desplegados y de la configuración del host (`daemon.json`, temporizador,
  `sysctl` y swap);
- contenedores, con su ID y su fecha de creación.

Las líneas `PLAN` que quedan en una segunda ejecución son acciones facturables no aprobadas en esa
ejecución (por ejemplo, crear los servidores de ambiente), no cambios. La prueba del 2026-11-03
terminó con `planned=4`. Desde entonces, el EULA de Nexus no aceptado figura como `UNCHANGED`, así que
la siguiente debería dar `planned=3`. La primera ejecución tras los cambios del 2026-11-03 también:
- crea el secreto del registro;
- despliega el registro;
- recrea Nexus una vez para mover su conector al puerto de reserva;
- reinicia Docker una vez en cada host por el nuevo `daemon.json`.

La segunda debe quedar sin cambios. Procedimiento manual equivalente:
[evidencia 15](../docs/evidencias/hu-01/15-procedimiento-idempotencia-aws.md).

## Ambientes dev, stage y prod (servidores por pares)

**Decisión (2026-11-03):** un servidor `t3.small` (2 vCPU, 2 GiB, 10 GiB gp3 cifrado) por ambiente.
Cada uno tiene su subred, su grupo de seguridad, su llave SSH y un `.env` solo con las
credenciales de su ambiente. `bootstrap-env.sh` prepara cada host: Docker, Compose, parada
automática y swap. Ni la red ni IAM cambian.

**Estado:** preparado y probado en local; **los servidores aún no existen** (crearlos requiere
autorización).

**Alternativas evaluadas:**

| Alternativa | Aislamiento | vCPU | Coste | Decisión |
|---|---|---|---|---|
| 3 × `t3.small`, probados por pares | Real: host, subred, grupo de seguridad y credenciales propios, verificado con tráfico | 2 a la vez por par; cabe en el límite de 5 | ≈ 0.08 USD/día de EBS + céntimos por sesión | **Elegida** |
| 3 × `m7i-flex.large` (8 GiB, capaces de ejecutar los servicios núcleo) | Real | 10 con todo encendido; cabe en la cuota real de 16, no en el límite de 5 | 0.30 USD/h encendidos + EBS | Descartada en HU-01: riesgo de presupuesto (15 USD) |
| Un host compartido con tres proyectos Compose | Débil: mismo núcleo, subred y grupo de seguridad | 2 | Bajo | Descartada: no cumple el aislamiento por red |
| Solo red, sin servidores | Configurado, sin tráfico | 0 | 0 | Descartada: no demuestra ambientes desplegados |

**Conflicto que se documenta:** el enunciado (p. 4, «Alcance de despliegue en la Parte 1») pide
desplegar los servicios núcleo y su middleware en los tres ambientes. Un `t3.small` (2 GiB) no
basta para eso. Tres `m7i-flex.large` caben en la cuota real (16 vCPU), pero junto a `ci` y `nexus`
suman 10 vCPU y unos 0.50 USD/h, fuera del límite de 5 y del presupuesto que fijó el equipo. HU-01
entrega los tres ambientes **aislados y aprovisionados**. El despliegue de las aplicaciones (E1.5)
exigirá subir el límite y el tamaño. Ese requisito **no puede demostrarse dentro de HU-01**.

**Prueba de aislamiento con tráfico** (FACTURABLE, ≈ 0.15 USD más el EBS de los ambientes).
Ejecutada el 2026-11-03/04 en dos sesiones, todas las fases en PASS (≈ 0.03 USD;
[evidencias](../docs/evidencias/hu-01/aws/aislamiento/README.md)):
```bash
bash infra/test-isolation.sh                          # --plan: fases y costo, sin AWS
bash infra/aws-session.sh login operator              # ventana MFA de 1 h
bash infra/test-isolation.sh --apply --phases=1,2,3   # pide 'PROBAR AISLAMIENTO'; detiene todo al terminar
bash infra/aws-session.sh login operator              # nueva ventana
bash infra/test-isolation.sh --apply --phases=4,5
```
Cada fase dura 10-15 minutos. Las cinco no caben en una ventana MFA de 1 h, y el script aborta,
deteniendo las instancias, a los 50 minutos.

| Fase | Servidores | Comprobaciones con `nc` desde los hosts |
|---|---|---|
| 1 | `env-dev` + `env-stage` | dev ↔ stage **bloqueado** en ambos sentidos; Docker, parada automática, swap y `.env` 0600 del ambiente |
| 2 | `env-dev` + `env-prod` | dev ↔ prod **bloqueado** |
| 3 | `env-stage` + `env-prod` | stage ↔ prod **bloqueado** |
| 4 | `ci` + `env-dev` | `ci → env:22` **permitido** (despliegue); `env → ci:8080` y `env → ci:9000` **bloqueados** |
| 5 | `nexus` + `env-dev` | `env → nexus:8082` **permitido** (registro); `nexus → env:22` **bloqueado** |

La fase 5 necesita el registro desplegado: ejecute antes `test-idempotency.sh`. Los resultados
quedan en `~/.circleguard/isolation/<marca UTC>/` con copias enmascaradas en `masked/`.

**Con todo encendido:** la cuota real (16 vCPU) ya lo admite. Si el equipo sube `QUOTA_VCPU_LIMIT`
a 10, se pueden encender los cinco servidores a la vez con
`bootstrap-all.sh --apply --approve all`. Hoy no se hace, por presupuesto.

## Integración de Jenkins con el registro

- **Imagen de Jenkins:** incluye `crane` (go-containerregistry v0.22.1, Apache 2.0), verificado
  con el sha256 publicado. Con él, Jenkins publica y descarga imágenes **sin el socket de Docker
  del host**, que le daría control de root sobre el servidor.
- **Configuración del contenedor:** `bootstrap-jenkins.sh` le pasa por su `.env` (0600 root):
  - `REGISTRY_ADDRESS`: IP privada de `nexus` y el 8082;
  - `REGISTRY_CI_USER`: `ci`;
  - `REGISTRY_CI_PASSWORD`: tomado de SSM.
- **Prueba:** `verify-infra.sh --registry` entra en `cg-jenkins` y, con esas variables:
  1. inicia sesión con una configuración temporal;
  2. copia `busybox:1.37.0` al registro (`circleguard/smoke-jenkins:1.37.0`);
  3. la descarga;
  4. comprueba que el digest coincide con el de origen.
- **TLS:** `crane --insecure` cifra el tráfico sin verificar el certificado autofirmado. Es el
  mismo criterio que `insecure-registries`.
- **E1.4:** el *pipeline* usará estas variables (o una credencial de Jenkins creada a partir de
  ellas) para publicar en `REGISTRY_ADDRESS/circleguard/<servicio>:<versión>`.

## Pipeline CI de Jenkins (HU-03)

El `Jenkinsfile` de la raíz y la Shared Library `jenkins/vars/` los carga Jenkins desde GitHub. La
configuración del controlador (plugins, biblioteca global `circleguard` y la instalación `sonarqube`) vive
en `bootstrap/jenkins/casc/jenkins.yaml` y `bootstrap/jenkins/plugins.txt`. Al cambiar los plugins se
cambia el tag de la imagen en `docker-compose.yml` (`-ciN`) para que `bootstrap-jenkins.sh` la reconstruya.

Credenciales (Manage Jenkins → Credentials → Global). Los valores se toman de SSM o de cada servicio y nunca se versionan:

| ID | Tipo | Uso |
|:---|:---|:---|
| `github-token` | Secret text | Leer el repositorio y la Shared Library |
| `sonar-token` | Secret text | Análisis de SonarQube (My Account → Security → Generate Tokens) |
| `nexus-credentials` | Usuario y contraseña | Publicar artefactos (opcional: sin `NEXUS_URL` se omite) |
| `discord-webhook` | Secret text | Notificación de fallos (opcional) |

Job: New Item → Multibranch Pipeline → Branch Sources: GitHub, repositorio del proyecto, credencial `github-token`,
Build Configuration: by Jenkinsfile. El disparo `githubPush()` requiere que GitHub alcance a Jenkins; como la
interfaz no se expone a Internet (ver `tunnel.sh`), el webhook llega por un relé o por una regla temporal del
grupo de seguridad, documentado en la evidencia de HU-03.

## Rotación de la contraseña del registro

```bash
bash infra/rotate-registry-password.sh                 # --plan: pasos, sin cambios
bash infra/rotate-registry-password.sh --apply         # pide 'ROTAR REGISTRO'
```
1. Guarda en memoria el valor actual, sin mostrarlo.
2. Escribe un valor nuevo en SSM (nueva versión del parámetro).
3. `bootstrap-registry.sh --apply`: reescribe el usuario `ci` y reinicia el registro.
4. `bootstrap-jenkins.sh --apply`: recrea el contenedor de Jenkins con la contraseña nueva;
   `jenkins_home` se conserva.
5. Comprueba que la nueva autentica (HTTP 200) y la anterior no (401), y ejecuta
   `verify-infra.sh --registry`.

**Requisitos:** el servidor `nexus` en ejecución; si `ci` está detenido, Jenkins recibe la
contraseña en su siguiente *bootstrap*.

**Efectos:** el registro y Jenkins se reinician; un *build* en curso se interrumpiría.

**Recuperación:** si falla la actualización del registro, el script restaura automáticamente el
valor anterior y vuelve a converger el registro. Si falla Jenkins, se repite
`bash infra/bootstrap-jenkins.sh --apply`. SSM guarda las versiones anteriores del parámetro.

## Proyección de costos de HU-01 (2026-11-03, estimación)

| Concepto | Coste estimado (USD) |
|---|---|
| Acumulado hasta el 2026-11-03 (sesión del 2026-11-02 y EBS desde entonces) | ≈ 0.18 |
| Prueba de idempotencia (`ci` + `nexus`, 1 h como máximo) | ≤ 0.21 |
| Prueba de aislamiento (5 fases de 15-20 min) | ≈ 0.15 |
| Ensayo de reconstrucción, nivel 1 | ≤ 0.21 |
| Dos sesiones de demostración de 3 h (`ci` + `nexus`) | ≈ 1.25 |
| EBS hasta el 2026-11-22: 55 GiB (`ci`, `nexus`) + 30 GiB (ambientes) | ≈ 2.75 + 1.50 |
| Reserva de transferencia de salida (3 GB) | 0.27 |
| **Total previsto hasta el 2026-11-22** | **≈ 6.5** (margen ≈ 8.5 frente a 15; ≈ 5.5 frente a la línea operativa de 12) |

**Coste de permanencia:**
- Con todo detenido: ≈ 0.22 USD/día (85 GiB de EBS).
- Encendidos: `ci` + `nexus` cuestan 0.2075 USD/h y cada ambiente 0.0258 USD/h.

Tras la evaluación hay que destruir la infraestructura (instrucción 4 del enunciado). Son
estimaciones con precios de referencia: la factura real se consulta en Billing y llega con retraso.

## Ensayo de reconstrucción desde cero

**Estado:** preparado, **no ejecutado**. Una persona del equipo que no participó en el despliegue
lo sigue usando solo este README. Instrucciones paso a paso para esa persona, con la evidencia
que debe entregar y los criterios de PASS:
[docs/evidencias/hu-01/ensayo-reconstruccion/](../docs/evidencias/hu-01/ensayo-reconstruccion/README.md).
Hay dos niveles:

**Nivel 1 · Otra estación de trabajo, sin destruir nada** (≈ 0.12-0.21 USD). Demuestra que la
documentación basta y que las llaves SSH se recuperan de su copia en SSM.
1. Clonar el repositorio en el sistema de archivos de WSL, con `~/.circleguard` y
   `~/.ssh/circleguard` inexistentes.
2. `bash infra/check-prerequisites.sh`: debe terminar con `fail=0`.
3. [Puesta en marcha](#puesta-en-marcha): `aws-session.sh init` y `login operator`. El único
   usuario operador tiene la MFA del responsable de la cuenta, así que el responsable escribe sus
   credenciales en la página de AWS.
4. `bash infra/bootstrap-secrets.sh --apply`: restaura las llaves desde SSM (`UPDATED`) sin crear
   secretos, salvo el del registro si aún no existe.
5. `bash infra/bootstrap-all.sh --plan`: revisar el costo.
6. `bash infra/test-idempotency.sh --apply --approve ci,nexus`. Es también la prueba de
   idempotencia de C3, así que no hace falta repetirla.

**Nivel 2 · Destrucción y reconstrucción reales** (exige autorización: **se pierden** los datos de
Jenkins, SonarQube, Nexus y el registro).
1. En CloudShell: `bash infra/teardown-cloudshell.sh --apply`, **sin** `--purge-secrets` para
   conservar los secretos. Ver [Detener o destruir](#detener-o-destruir).
2. En la estación de trabajo, `bash infra/bootstrap-all.sh --apply --approve ci,nexus`. Crea la
   red, reimporta las llaves, crea las instancias y despliega las herramientas. Después,
   `bash infra/test-isolation.sh --apply` crea y prueba los ambientes por pares.
3. `bash infra/verify-infra.sh` y `bash infra/verify-infra.sh --registry --roles=ci,nexus`.
4. Una segunda ejecución de `bootstrap-all.sh` (o `test-idempotency.sh`) debe terminar sin cambios.
5. Parada.

El registro local de costos de la estación de trabajo no ve la destrucción hecha en CloudShell:
su estimación queda por encima del costo real, que se consulta en Billing.

**Pasos que requieren intervención humana, y por qué** (todo lo demás lo hacen los scripts):

| Paso | Frecuencia | Por qué no se automatiza |
|---|---|---|
| MFA de la cuenta raíz y creación de IAM (`bootstrap-iam.sh --apply --approve iam`) | Una vez por cuenta | Requiere la identidad administrativa, que los roles de HU-01 no tienen por diseño |
| Contraseña de consola y MFA de los usuarios del operador y de teardown | Una vez por persona | Credenciales personales: nunca pasan por un script |
| `aws-session.sh login operator` y, si hace falta, `unlock` (código MFA) | Cada sesión | Credenciales temporales con MFA; ningún script recibe contraseñas ni códigos |
| `--approve <rol>` y las frases `DETENER`, `DESTRUIR circleguard`, `PROBAR IDEMPOTENCIA`, `PROBAR AISLAMIENTO` y `ROTAR REGISTRO` | Cada operación facturable, destructiva o disruptiva | Control humano del costo, de la pérdida de datos y de los reinicios |
| Lectura de la cuota de vCPU (`aws-session.sh login bootstrap` y `bootstrap-quota.sh`) | Antes de cambiar `QUOTA_VCPU_LIMIT` | Solo la identidad administrativa puede leer Service Quotas |
| `REGISTRY_BACKEND`, `ENV_SERVERS`, `QUOTA_VCPU_LIMIT` y presupuesto (el EULA de Nexus ya está decidido: no se acepta) | Cuando el equipo decida | Decisiones contractuales y económicas |
| Destrucción en CloudShell con el usuario de teardown | Al cerrar la evaluación | Separación de identidades: el operador no puede destruir |

## Verificación

```bash
bash infra/verify-infra.sh                  # --health --isolation --credentials
bash infra/verify-infra.sh --health --roles=ci,nexus   # solo los servidores encendidos
bash infra/verify-infra.sh --isolation      # flujos entre servidores probados con nc desde los hosts
bash infra/verify-infra.sh --registry --roles=ci,nexus   # publica y descarga una imagen desde ci
```
No cambia la infraestructura; `--registry` solo escribe en el registro una imagen de prueba fija
(`circleguard/smoke-busybox:1.37.0`), con una configuración de Docker temporal que se borra al
terminar. Termina con código 1 si alguna comprobación falla. Además de `PASS` y `FAIL` informa
`PENDING` para lo que espera una decisión o servidores que no existen, sin contarlo como superado:
- con `REGISTRY_BACKEND=nexus`, que el EULA de Nexus no esté aceptado. Con `distribution`, el EULA no aceptado es el estado decidido (`PASS`), y se comprueba que el conector Docker de Nexus no está publicado;
- el aislamiento de `dev`, `stage` y `prod`: se comprueba en la configuración (subred propia,
  grupo de seguridad propio, ninguna regla entre ambientes, solo referencias a `ci` y `nexus`),
  pero no con tráfico, porque no hay servidores de ambiente.

`--health` también comprueba, en cada servidor, Docker, que la parada automática está
**programada** (temporizador en espera), el swap y la memoria en uso, y registra la memoria de
cada contenedor (`docker stats --no-stream`). Un contenedor detenido o ausente, o un Docker que
no responde, se informa como tal, nunca como consumo cero.

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
   Súbalo tal cual: descomprimirlo y volver a comprimirlo en Windows cambia su estructura.
3. En CloudShell:
   ```bash
   tar -xzf circleguard-teardown.tgz
   bash infra/teardown-cloudshell.sh                          # pide el código MFA; inventario y plan
   bash infra/teardown-cloudshell.sh --apply                  # destruye: exige escribir 'DESTRUIR circleguard'
   bash infra/teardown-cloudshell.sh --purge-secrets --apply  # además borra /circleguard/* de SSM
   ```
- Solo actúa sobre recursos con las etiquetas `Project=circleguard` y `ManagedBy=infra-bootstrap`.
- Se pide **un** código MFA por ejecución. La sesión del rol dura 30 minutos: la AWS CLI descarta
  las credenciales en caché a las que les quedan menos de 15, así que con sesiones de 15 minutos
  pedía un código en cada llamada. Si el perfil ya existía con otro valor (900 s en versiones
  anteriores), el script lo corrige; al salir borra las credenciales en caché.
- El perfil del rol vive en `~/.circleguard/aws/.aws/config`, no en `~/.aws/config`: `aws configure
  list` fuera del script muestra las credenciales propias de CloudShell (el usuario de teardown).
- La llave privada local y su copia en SSM se conservan, salvo que se use `--purge-secrets`.

## Validación local gratuita (`--target local`)

Valida en Docker Desktop, sin AWS, los mismos stacks y scripts de configuración que se usarán en
EC2. Publica solo en `127.0.0.1`, con secretos en `~/.circleguard/secrets` (fuera del repositorio
y de OneDrive). Docker Desktop tiene unos 7.4 GiB: **valide una herramienta a la vez**.

```bash
bash infra/bootstrap-secrets.sh --target local --apply
bash infra/bootstrap-jenkins.sh --target local --apply      # http://localhost:8080
bash infra/bootstrap-sonarqube.sh --target local --apply    # http://localhost:9000
bash infra/bootstrap-nexus.sh --target local --apply        # http://localhost:8081
bash infra/bootstrap-registry.sh --target local --apply     # registro en https://localhost:5000 (usuario ci)
bash infra/verify-infra.sh --target local --registry         # publica y descarga una imagen de prueba
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
| `ci` y `nexus` | 22/tcp | Solo `ADMIN_CIDRS` (llave SSH, sin contraseña). Además, `ci` puede llegar por SSH a los grupos de dev, stage y prod |
| `ci`: Jenkins | 8080/tcp | Escucha **solo en 127.0.0.1** del host: se accede con `tunnel.sh jenkins` |
| `ci`: SonarQube | 9000/tcp | Escucha **solo en 127.0.0.1** del host (comparte servidor con Jenkins): `tunnel.sh sonarqube`. Ninguna regla de red |
| `nexus` | 8081/tcp (UI/API) | `ci` por la red privada. Administración con `tunnel.sh nexus` |
| `nexus` | 8082/tcp (registro Docker) | `ci` y los grupos de dev, stage y prod por la red privada. Con `REGISTRY_BACKEND=distribution`, CNCF Distribution con TLS (certificado autofirmado) y el usuario `ci`; los clientes Docker de la VPC confían en él mediante `insecure-registries` limitado a la subred `tools` |
| salida de todos | 80, 443/tcp | Paquetes, imágenes y plugins |

**Ninguna interfaz HTTP está abierta a Internet**, ni siquiera para la IP del operador. El tráfico
administrativo viaja cifrado dentro del túnel SSH, así que no hace falta TLS para la administración
en la Parte 1. TLS para los servicios expuestos corresponde a E2.6.

Volúmenes Docker: `circleguard-jenkins_jenkins_home`,
`circleguard-sonarqube_{sonarqube_data,sonarqube_extensions,sonarqube_logs,sonar_db_data}`,
`circleguard-nexus_nexus-data` y `circleguard-registry_registry-data`. En EC2 viven en el EBS
cifrado de `ci` (Jenkins y SonarQube) y de `nexus` (Nexus y registro). La parada automática y
`teardown.sh --stop` conservan los volúmenes.

## Solución de problemas

| Síntoma | Causa y solución |
|---|---|
| `No hay una sesión AWS válida para el perfil ...` | Inicie la sesión que indica el mensaje: `bash infra/aws-session.sh login operator` (o `teardown`) |
| `La identidad ... no corresponde a la capacidad ...` | La operación necesita otro rol (por ejemplo, operación fuera de la ventana de 1 h): vuelva a iniciar sesión |
| `La estimación supera el presupuesto de HU-01` | Estimación local: revise el costo real en Billing y consulte al equipo antes de continuar |
| `Sin acceso SSH` | Su IP pública cambió: vuelva a ejecutar `bootstrap-network.sh --apply` (actualiza `ADMIN_CIDRS`) o defínala |
| La UI no responde en `http://<ip-publica>:8080` | Es intencional: las UIs no se exponen a Internet. Use `bash infra/tunnel.sh jenkins` y abra `http://localhost:8080` |
| `No hay una instancia '<rol>' en ejecución` | Créela o iníciela con `bootstrap-servers.sh --apply --approve <rol>` (`ci` o `nexus`) |
| `EULA de Nexus Community Edition no aceptado` (`UNCHANGED` o `PASS`) | Es el estado decidido por el equipo: Nexus queda sin repositorio y el registro es CNCF Distribution. No requiere ninguna acción |
| La instancia se detuvo sola | Es la parada automática (`AUTO_STOP_HOURS`): iníciela con `bootstrap-servers.sh --apply --approve <rol>`; los stacks arrancan con Docker |
| Aviso «parada automatica en 5 minutos» | Para seguir: `sudo shutdown -c && sudo systemctl restart circleguard-autostop.timer`. Solo `shutdown -c` deja el servidor sin parada programada |
| `parada automática programada ... (esperado 'waiting', obtenido 'elapsed')` | El temporizador venció (por ejemplo, tras `shutdown -c`): `sudo systemctl restart circleguard-autostop.timer`, o vuelva a ejecutar el *bootstrap* de la herramienta |
| El puerto 5432 está ocupado en Windows | Un PostgreSQL nativo usa ese puerto: el middleware local no puede publicar 5432 mientras siga activo. Deténgalo (es su decisión) o use otra máquina. Los scripts nunca lo tocan |
| El puerto 8082 está ocupado en Windows | En local, el registro se publica en 5000 (`LOCAL_NEXUS_DOCKER_HOST_PORT`) |
| `el puerto 8082 lo publica cg-nexus` (registro) | Nexus aún tiene el conector en el 8082: ejecute antes `bootstrap-nexus.sh --apply` (con `REGISTRY_BACKEND=distribution` lo mueve a `127.0.0.1:18082`). `bootstrap-all.sh` ya lo hace en ese orden |
| `http: server gave HTTP response to HTTPS client` o `x509` al publicar en el registro | El cliente Docker no tiene la subred `tools` en `insecure-registries`: vuelva a ejecutar el *bootstrap* de ese host (escribe `/etc/docker/daemon.json`) |
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
- **Registro (CNCF Distribution):**
  - TLS **sin autenticación del servidor**: el certificado es autofirmado y los clientes de la
    VPC no lo verifican.
  - Todo usuario autenticado puede publicar; solo existe `ci`.
  - La contraseña de `ci` llega a Jenkins como variable de entorno del contenedor (desde su `.env`
    0600 root). Root en el host la ve con `docker inspect`, y los futuros *jobs* del controlador
    podrían leerla. E1.4 debería pasarla a una credencial de Jenkins, que la enmascara en los logs.
  - Las etiquetas no son inmutables: el *pipeline* no debe reutilizarlas.
  - El htpasswd se genera en el host desde stdin, con bcrypt.
  - Detalle y mejoras en [registro-artefactos.md](../docs/arquitectura/registro-artefactos.md).
- **Riesgo residual:** las migraciones Flyway `V2`/`V3` de auth-service crean usuarios de prueba
  con una contraseña conocida y la revelan en un comentario. No se modifican (decisión X-2); queda
  para E2.6.
- `scan-secrets.sh` debe terminar en `PASS` antes de cada commit.

## Dependencias con otros entregables (no implementadas en HU-01)

- **E1.3:** imágenes de los microservicios y *compose* por ambiente que consumirá
  `/opt/circleguard/<env>/.env`; usuarios de *push*/*pull* del registro.
- **E1.4:** Jenkinsfile, plugins de *pipeline*, *webhook* de GitHub, conexión con SonarQube
  (*quality gate*) y acceso de Jenkins a Docker. Jenkins y SonarQube comparten el servidor `ci` y
  SonarQube solo escucha en `127.0.0.1` del host: el contenedor de Jenkins lo alcanzará mediante
  una red Docker compartida entre ambos stacks, sin abrir ningún puerto.
- **E1.5:** llaves de Jenkins hacia los ambientes, despliegue, promoción y *rollback*.
- **Gradle:** `gradle/wrapper/gradle-wrapper.jar` no está versionado (lo excluye `*.jar`), así que
  `./gradlew` no funciona en un clon limpio. Se recomienda resolverlo en E1.4.

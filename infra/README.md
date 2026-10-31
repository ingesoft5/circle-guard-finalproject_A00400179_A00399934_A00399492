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
> Detenga las instancias al terminar cada sesión (`infra/teardown.sh --stop`).

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
| `config/aws.env` | Configuración **no secreta**: región, CIDR, tipos, puertos, precios de referencia |
| `config/envs/<env>.env` | Subred, tipo y disco de cada ambiente |
| `config/secrets.catalog` | **Nombres** y generadores de los secretos (nunca valores) |
| `config/iam/hu01-operator-policy.json` | Política IAM de mínimo privilegio para operar (crear, configurar, detener, verificar) |
| `config/iam/hu01-teardown-policy.json` | Permisos destructivos, separados: se adjuntan **solo** para `teardown.sh --destroy` |
| `bootstrap/lib/*.sh` | Librerías: utilidades comunes, AWS y transporte SSH/local |
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
3. **Identidad IAM del operador. No use la cuenta raíz: los scripts la rechazan.** Créela en la
   consola con la política [`config/iam/hu01-operator-policy.json`](config/iam/hu01-operator-policy.json)
   y configúrela con `aws configure --profile circleguard-hu01` (o `aws sso login`). Las credenciales
   quedan en `~/.aws`, fuera del repositorio. Indique el perfil en
   `infra/config/operator.local.env` (copie [`operator.local.env.example`](config/operator.local.env.example)).

   La política del operador:
   - solo permite las acciones que usan los scripts (contraste estático en
     [`06-iam-minimo-privilegio.txt`](../docs/evidencias/hu-01/06-iam-minimo-privilegio.txt));
   - funciona únicamente en `us-east-2`;
   - exige la etiqueta `Project=circleguard` para crear o modificar recursos;
   - limita EC2 a `t3.small`, `t3.medium` y `t3.large` con IMDSv2, y los discos a gp3 cifrados de
     40 GiB como máximo;
   - acepta solo AMIs de Canonical y secretos bajo `/circleguard/*`;
   - **no incluye ninguna acción destructiva.**

   Para destruir, adjunte temporalmente
   [`hu01-teardown-policy.json`](config/iam/hu01-teardown-policy.json) y retírela al terminar.
   Valide ambas políticas con IAM Access Analyzer antes de usarlas (es gratuito).
4. **Docker Desktop** con integración WSL, solo para la validación local y para Gitleaks.
5. Los scripts se ejecutan desde la raíz del repositorio con `bash infra/<script>.sh`.

## Configuración

- `config/aws.env`: región `us-east-2`, zona `us-east-2a`, CIDR `10.20.0.0/16`, tipos
  (Jenkins `t3.medium`, SonarQube `t3.large`, Nexus `t3.large`), puertos y precios de referencia.
- `config/envs/{dev,stage,prod}.env`: subredes `10.20.{10,20,30}.0/24`, `t3.small`, 20 GiB.
- `config/operator.local.env` (ignorado): `AWS_PROFILE` y `ADMIN_CIDRS`. Si `ADMIN_CIDRS` está
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

### Presupuesto por recurso (topología A, precios de referencia On-Demand en us-east-2)

Confirme las tarifas vigentes antes de cada sesión con `bash infra/bootstrap-servers.sh --prices`
(AWS Pricing API, solo lectura).

| Recurso | Cantidad | Tarifa | Encendido (USD/h) | Detenido | USD/día (24 h encendido) | USD/mes (730 h) |
|---|---|---|---|---|---|---|
| EC2 Jenkins `t3.medium` | 1 | 0.0416/h | 0.0416 | 0 | 1.00 | 30.37 |
| EC2 SonarQube `t3.large` | 1 | 0.0832/h | 0.0832 | 0 | 2.00 | 60.74 |
| EC2 Nexus `t3.large` | 1 | 0.0832/h | 0.0832 | 0 | 2.00 | 60.74 |
| EC2 dev, stage y prod `t3.small` | 3 | 0.0208/h c/u | 0.0624 | 0 | 1.50 | 45.55 |
| IPv4 pública (automática, sin Elastic IP) | 6 | 0.005/h c/u | 0.0300 | 0 (se libera) | 0.72 | 21.90 |
| EBS gp3 cifrado (30 + 30 + 40 + 3×20 GiB) | 160 GiB | 0.08/GB-mes | 0.0175 | **0.0175/h** | 0.42 | 12.80 |
| Transferencia de salida | < 1 GB | 100 GB/mes gratis | 0 | 0 | 0 | 0 |
| SSM Parameter Store estándar y KMS `aws/ssm` | 35 parámetros | Sin cargo (capa gratuita de KMS) | 0 | 0 | 0 | 0 |
| VPC, subredes, IGW, rutas, grupos de seguridad, pares de llaves | — | Sin cargo | 0 | 0 | 0 | 0 |
| NAT Gateway, balanceadores, Elastic IP, *snapshots*, ráfagas T3 | — | **No se usan** | 0 | 0 | 0 | 0 |
| **Total** | | | **0.318** | **0.42 USD/día** | **7.63** | **232.1** |

**Encendida 24/7, la plataforma agota los 100 USD en unos 13 días.** Por eso se trabaja por sesiones.

### Ejecución por sesiones (estimación para completar HU-01)

Cada sesión empieza con la autorización de las operaciones facturables que contiene y termina con
`bash infra/teardown.sh --stop`. El costo por hora con las seis instancias encendidas es de 0.300
USD (EC2 e IPv4), más el EBS, que se cobra mientras los volúmenes existen.

| Sesión | Contenido | Operaciones facturables que se autorizan | Duración | Costo estimado |
|---|---|---|---|---|
| S0 | IAM, AWS CLI, `--prices`, `bootstrap-all.sh --plan`, Access Analyzer | Ninguna | — | 0 |
| S1 | Red, secretos y llaves (`bootstrap-network.sh` y `bootstrap-secrets.sh --apply`) | Ninguna (recursos sin cargo) | — | 0 |
| S2 | Jenkins: crear, configurar, verificar y segunda ejecución | `run-instances` jenkins | 1.5 h | 0.07 |
| S3 | SonarQube y Nexus: crear y configurar (Nexus, según la decisión sobre el EULA) | `run-instances` sonarqube y nexus | 2 h | 0.35 |
| S4 | dev, stage y prod: crear, configurar, aislamiento y credenciales | `run-instances` ×3 (con las 6 encendidas) | 2 h | 0.60 |
| S5 | Idempotencia: `bootstrap-all` ×2 con *snapshot* y `diff` | `start-instances` ×6 si estaban detenidas | 1.5 h | 0.45 |
| S6 | Reconstrucción desde cero: `teardown --destroy` y `bootstrap-all --approve all` | `terminate-instances` ×6 y `run-instances` ×6 | 3 h | 0.90 |
| — | Contingencia para depuración y reintentos | Según la sesión | 6 h | 1.80 |
| — | EBS mientras existe la plataforma (hasta 10 días) | — | 10 días | 4.21 |
| **Total HU-01** | | | | **≈ 8.4 USD**, unos **12.6 USD con un 50 % de margen** |

**Barreras de costo:**
- Configure **AWS Budgets** con alertas en 10, 25, 50 y 75 USD (los dos primeros presupuestos no
  tienen cargo; verifíquelo).
- Al cerrar cada sesión, ejecute `teardown.sh --stop` y confirme que no queda nada encendido:
  ```bash
  aws ec2 describe-instances --region us-east-2 \
    --filters Name=tag:Project,Values=circleguard Name=instance-state-name,Values=running \
    --query 'Reservations[].Instances[].InstanceId'
  ```
- Si el consumo supera **25 USD** antes de terminar HU-01, se detiene todo y se revisa.
- Al finalizar la evaluación, ejecute `teardown.sh --destroy`, como pide el enunciado.
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
bash infra/teardown.sh --stop               # detiene las instancias (conserva datos)
bash infra/teardown.sh --destroy            # elimina instancias (y sus DATOS), red y pares de llaves de HU-01
bash infra/teardown.sh --destroy --purge-secrets   # además borra /circleguard/* de SSM
```
`--destroy` requiere tener adjunta, además de la del operador, la política
`config/iam/hu01-teardown-policy.json`.
- `--destroy` lista los recursos afectados y exige escribir `DESTRUIR circleguard`.
  `--purge-secrets` exige una segunda frase.
- Solo actúa sobre recursos con las etiquetas `Project=circleguard` y `ManagedBy=infra-bootstrap`.
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
bash infra/teardown.sh --target local --stop                # nunca borra volúmenes
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
| `No hay credenciales AWS válidas` | Configure el perfil IAM (`aws configure --profile ...`) y `AWS_PROFILE` en `operator.local.env` |
| `Se detectó la cuenta raíz` | Use una identidad IAM con la política de `config/iam/` |
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

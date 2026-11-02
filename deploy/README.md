# Empaquetamiento inmutable · HU-02

Esta carpeta contiene el empaquetamiento reproducible de CircleGuard: nueve imágenes
(los 8 microservicios y el cliente web) y un stack Docker Compose por ambiente (`dev`, `stage`,
`prod`). No modifica el código base: los servicios se configuran con variables de entorno de
Spring Boot y el cliente web se adapta en tiempo de build dentro de la imagen.

## Contenido

| Ruta | Función |
|---|---|
| `build-images.sh` | Construye las 9 imágenes con una versión semántica; rechaza `latest` |
| `publish-images.sh` | Publica las 9 imágenes en el registro y muestra los digests |
| `verify-images.sh` | Comprueba usuario no root, etiqueta OCI de versión, IDs y digests |
| `compose-up.sh <env>` | Levanta `dev`, `stage` o `prod` y espera los healthchecks |
| `compose-down.sh <env>` | Detiene el ambiente sin borrar volúmenes |
| `compose/` | Stack común + un archivo Compose por ambiente |
| `registry/` | Registro OCI local equivalente mientras el EULA de Nexus está pendiente |
| `logs/` | Salidas de build (ignoradas por Git) |

## Prerrequisitos

- Docker Engine o Docker Desktop con el plugin `docker compose` v2.20 o superior.
- Bash 4 o superior (WSL Ubuntu, Linux o Git Bash).
- Las 7 máquinas de despliegue necesitan **solo Docker y este repositorio**; no se asume WSL.
- El registro debe estar disponible en `IMAGE_REGISTRY` (por defecto `localhost:5000`).

> **Docker no está instalado en el equipo actual.** Hasta instalarlo no se pueden generar las
> evidencias de build/publicación; los archivos y la configuración sí están listos.

### Instalar Docker (WSL para desarrollo, Docker Engine para las 7 máquinas)

**Windows + WSL (equipo de desarrollo).** La opción más simple es Docker Desktop con
*Use the WSL 2 based engine* y la integración de la distribución Ubuntu activada. Después, en WSL:

```bash
docker --version
docker compose version   # debe ser v2.20 o superior
```

**Linux / WSL nativo (hosts de las 7 máquinas).** Instale Docker Engine y el plugin Compose desde
el repositorio oficial de Docker para su distribución, habilite el servicio y agregue el usuario al
grupo `docker`:

```bash
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
docker run --rm hello-world
docker compose version
```

No se requieren rutas de WSL ni PowerShell: todos los scripts funcionan igual en Ubuntu, otra
distribución Linux o Git Bash. Si una máquina es ARM, valide `osixia/openldap:1.5.0` (no publica un
digest multi-arquitectura) antes de usarla.

## Flujo completo (dev)

```bash
# 1. Registro equivalente (Nexus sigue con EULA pendiente)
docker compose -f deploy/registry/docker-compose.yml up -d

# 2. Credenciales locales fuera del repositorio (HU-01)
#    ~/.circleguard/dev.env y ~/.circleguard/dev-app.env

# 3. Construir y publicar la versión
./deploy/build-images.sh 1.0.0
./deploy/publish-images.sh 1.0.0

# 4. Verificar las imágenes
./deploy/verify-images.sh --evidence 1.0.0

# 5. Levantar el stack dev y esperar los healthchecks
./deploy/compose-up.sh dev
#    Abrir http://localhost:3000

# 6. Evidencias de Compose
docker compose --env-file deploy/compose/dev.env \
  --env-file "$HOME/.circleguard/dev.env" \
  --env-file "$HOME/.circleguard/dev-app.env" \
  -f deploy/compose/docker-compose.common.yml \
  -f deploy/compose/docker-compose.dev.yml config --no-interpolate > docs/evidencias/hu-02/01-compose-config.txt
./deploy/compose-up.sh dev 2>&1 | tee docs/evidencias/hu-02/03-compose-health.txt

# 7. Detener sin borrar volúmenes
./deploy/compose-down.sh dev
```

## Stage y prod

`deploy/compose/stage.env` y `prod.env` dejan `IMAGE_REGISTRY` e `IMAGE_TAG` vacíos a propósito:
el despliegue debe indicarlos y Compose falla si faltan. En los hosts de ambiente las credenciales
están en `/opt/circleguard/<env>/.env` (HU-01).

```bash
IMAGE_REGISTRY=nexus.example:8082 IMAGE_TAG=1.0.0 \
CG_ENV_FILE=/opt/circleguard/stage/.env ./deploy/compose-up.sh stage
```

> **Prod** publica el cliente web solo en `127.0.0.1` hasta que exista el ingress con TLS (E2.6).
> Se puede acceder por túnel SSH o con un proxy inverso delante.

## Etiquetado y nombres

```
${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/circleguard-<servicio>:<MAJOR.MINOR.PATCH>
${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/circleguard-web:<MAJOR.MINOR.PATCH>
```

- Solo se aceptan versiones semánticas (`1.0.0`, `1.2.3-rc.1`). `latest` se rechaza.
- Cada imagen lleva etiquetas OCI `version`, `revision` y `created`.
- No se usan tags flotantes para las imágenes propias; las imágenes base están fijadas por
  `tag@sha256`.
- El repositorio Docker de Nexus está configurado con `writePolicy: allow_once`, de modo que un
  tag ya publicado no se puede sobrescribir.

## Variables de entorno

| Archivo | Contenido | Versionado |
|---|---|---|
| `deploy/compose/<env>.env` | Proyecto, registro, tag, puertos, límites, política de reinicio | Sí (sin secretos) |
| `~/.circleguard/dev.env` + `dev-app.env` | Credenciales locales (HU-01) | No |
| `/opt/circleguard/<env>/.env` | Credenciales del host del ambiente (HU-01) | No |

La sustitución de variables de Compose se hace con `--env-file`; los servicios reciben las
credenciales con `environment:` y las variables `SPRING_*` para apuntar a los contenedores
(`SPRING_DATASOURCE_URL`, `SPRING_NEO4J_URI`, `SPRING_KAFKA_BOOTSTRAP_SERVERS`,
`SPRING_DATA_REDIS_HOST`, `SPRING_LDAP_URLS`).

## Healthchecks

- Middleware: `pg_isready`, `cypher-shell`, `kafka-broker-api-versions`, `redis-cli ping`,
  `ldapsearch`, `zookeeper-shell`.
- Servicios: sonda HTTP al puerto propio que acepta `2xx`, `3xx`, `400`, `401`, `403` o `404`.
  No se añadió Actuator (restricción de HU-02: no tocar el código base); la sonda demuestra que
  el proceso acepta HTTP, no que todas las dependencias estén sanas.
- Web: `wget --spider http://127.0.0.1:8080/healthz`.
- `web` espera a que los 8 servicios estén `healthy`.

## Cliente web sin cambios en el código base

El Dockerfile de `mobile/` reescribe en tiempo de build las URLs absolutas
`http://localhost:<puerto>` por rutas del mismo origen (`/auth`, `/identity`, ...) y nginx las
redirige a cada servicio. El repositorio no se modifica y la misma imagen funciona en cualquier
host, sin rebuild por ambiente.

## Limitaciones y siguientes pasos

- Nexus: publicar allí requiere aceptar el EULA y crear usuarios de push/pull (HU-01 los deja
  pendientes). Hasta entonces se usa `registry:2` como registro equivalente.
- Actuator: añadirlo (una línea en el Gradle raíz) permitiría healthchecks de readiness reales.
- Ingress/TLS: el cliente web es el único puerto publicado; el TLS y el dominio corresponden a
  E2.6.
- Reproducibilidad byte a byte: Gradle conserva timestamps en los JAR. La versión, las imágenes
  base y el lockfile de npm están fijados; para bit-a-bit haría falta configurar JAR reproducible
  (cambio en `build.gradle.kts`, fuera de HU-02).
- La sonda HTTP no distingue un servicio con una dependencia caída de uno sano. Es una decisión
  explícita para no tocar el código base.

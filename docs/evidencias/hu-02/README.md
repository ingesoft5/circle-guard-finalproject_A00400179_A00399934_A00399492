# Evidencias de HU-02 · Imágenes Docker inmutables

**Estado: implementación lista, evidencias pendientes de Docker.**
El equipo de desarrollo aún no tiene Docker instalado (ni en Windows ni en WSL) y el EULA de
Nexus sigue pendiente. Por eso las salidas reales de `docker build`, `docker inspect`, el listado
del registro y los healthchecks se generarán cuando Docker esté disponible; este documento deja
los comandos exactos y el estado de cada criterio.

## Matriz de criterios

| Criterio | Implementación | Evidencia |
|---|---|---|
| Dockerfile multi-stage para los 8 servicios y el cliente web | `services/*/Dockerfile` (8) y `mobile/Dockerfile` | `04-build.txt`, `deploy/logs/*.log` |
| Ejecución con usuario no root | UID/GID 10001 en servicios; UID 101 en web | `02-docker-inspect.txt` (`user=10001:10001`, `user=101`) |
| Tags semánticos; prohibido `latest` | `deploy/lib.sh` valida semver y rechaza `latest`; Compose exige `IMAGE_TAG` | `04-build.txt`, `01-compose-config-*.txt` |
| Imágenes publicadas en Nexus o registro equivalente | `deploy/registry/` (`registry:2`) mientras el EULA de Nexus está pendiente; `deploy/publish-images.sh` | `05-registry.txt` |
| Un Compose por ambiente con healthchecks | `deploy/compose/docker-compose.{common,dev,stage,prod}.yml` | `01-compose-config-*.txt`, `03-compose-health.txt` |
| Un archivo Compose para dev, stage y prod | `deploy/compose/docker-compose.{dev,stage,prod}.yml` | Los tres `config` |
| Evidencias de build, inspect y registro | Scripts + este documento | Archivos de esta carpeta |

## Requisitos previos

```bash
docker --version
docker compose version        # v2.20 o superior
bash --version
```

Si Docker no está instalado, ver [`deploy/README.md`](../../../deploy/README.md). No se requiere
WSL: los hosts de despliegue pueden ser Linux con Docker Engine.

## 1. Configuración de Compose por ambiente

Use `--no-interpolate`: muestra la estructura y los healthchecks con los placeholders
`${...}`, **sin** resolver las credenciales. No use `docker compose config` sin ese flag para
evidencias: imprimiría los secretos resueltos.

```bash
docker compose --env-file deploy/compose/dev.env \
  --env-file "$HOME/.circleguard/dev.env" \
  --env-file "$HOME/.circleguard/dev-app.env" \
  -f deploy/compose/docker-compose.common.yml \
  -f deploy/compose/docker-compose.dev.yml config --no-interpolate \
  > docs/evidencias/hu-02/01-compose-config-dev.txt

# stage y prod: sustituya IMAGE_REGISTRY e IMAGE_TAG y use /opt/circleguard/<env>/.env
```

## 2. Build de las 9 imágenes

```bash
./deploy/build-images.sh 1.0.0 | tee docs/evidencias/hu-02/04-build.txt
```

La salida incluye la versión, el commit, la fecha y el ID de cada imagen. El log completo queda
en `deploy/logs/build-1.0.0-*.log` (ignorado por Git).

## 3. Verificación de usuario no root, versión y digests

```bash
./deploy/verify-images.sh --evidence 1.0.0
```

Genera `02-docker-inspect.txt` con una línea por imagen:

```
user=10001:10001 version=1.0.0 revision=<commit> id=sha256:... digests=[...]
```

El script falla si alguna imagen corre como root o si la etiqueta de versión no coincide.

## 4. Publicación en el registro

```bash
# Registro equivalente local (Nexus con EULA pendiente)
docker compose -f deploy/registry/docker-compose.yml up -d
./deploy/publish-images.sh 1.0.0 | tee docs/evidencias/hu-02/05-registry.txt

# Listado del registro
curl -fsS http://localhost:5000/v2/_catalog | tee -a docs/evidencias/hu-02/05-registry.txt
curl -fsS http://localhost:5000/v2/circleguard/circleguard-auth-service/tags/list | tee -a docs/evidencias/hu-02/05-registry.txt
```

Cuando el equipo acepte el EULA de Nexus:

```bash
IMAGE_REGISTRY=<host-nexus>:8082 REGISTRY_USER=<usuario-push> REGISTRY_PASSWORD=... \
  ./deploy/publish-images.sh 1.0.0
```

## 5. Stack dev con healthchecks

```bash
./deploy/compose-up.sh dev 2>&1 | tee docs/evidencias/hu-02/03-compose-health.txt
docker compose --env-file deploy/compose/dev.env \
  --env-file "$HOME/.circleguard/dev.env" \
  --env-file "$HOME/.circleguard/dev-app.env" \
  -f deploy/compose/docker-compose.common.yml \
  -f deploy/compose/docker-compose.dev.yml ps \
  | tee -a docs/evidencias/hu-02/03-compose-health.txt
```

Resultado esperado: 15 contenedores (`postgres`, `neo4j`, `zookeeper`, `kafka`, `redis`,
`openldap`, 8 servicios y `web`) con estado `healthy`. La UI queda en <http://localhost:3000>.

## 6. Cierre

```bash
./deploy/compose-down.sh dev
./infra/scan-secrets.sh
```

Antes de versionar una salida, compruebe que no contiene contraseñas, tokens ni rutas de usuario
sensibles. Los logs de `deploy/logs/` no se versionan.

## Estado de los bloqueos

| Bloqueo | Impacto | Resolución |
|---|---|---|
| Docker no instalado | No se pueden generar las evidencias 1–5 | Instalar Docker Engine/Desktop |
| EULA de Nexus pendiente | No se puede publicar en Nexus | Decisión del equipo; mientras tanto, `registry:2` |
| Servidores AWS no creados | No hay host de `dev/stage/prod` | HU-01 Fase 5 / HU-06 |

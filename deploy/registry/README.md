# Registro OCI local para las evidencias de HU-02

Nexus Repository es el registro oficial del proyecto, pero su **EULA sigue pendiente**
(`NEXUS_ACCEPT_EULA=false`, decisión de HU-01). Mientras el equipo decide, HU-02 se evidencia
contra un **registro equivalente**: Docker Distribution (`registry:2.8.3`), que implementa la
API OCI Distribution estándar.

> Este registro escucha solo en `127.0.0.1`, no tiene autenticación y **no es para producción**.
> En los servidores de ambiente se usará Nexus en `nexus:8082/circleguard/...` cuando el EULA
> esté aceptado.

## Arrancar y detener

```bash
docker compose -f deploy/registry/docker-compose.yml up -d
docker compose -f deploy/registry/docker-compose.yml ps
docker compose -f deploy/registry/docker-compose.yml down
```

El puerto se puede cambiar con `REGISTRY_PORT` (por defecto `5000`).

## Publicar y comprobar

```bash
./deploy/build-images.sh 1.0.0
./deploy/publish-images.sh 1.0.0
curl -fsS http://localhost:5000/v2/_catalog
curl -fsS http://localhost:5000/v2/circleguard/circleguard-auth-service/tags/list
```

## Limpieza

El volumen `circleguard-registry_registry-data` conserva las imágenes. Si hay que borrarlo, debe
hacerse **nombrándolo explícitamente** y con aprobación; nunca con `docker system prune`.

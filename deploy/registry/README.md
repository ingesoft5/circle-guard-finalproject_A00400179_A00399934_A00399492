# Registro OCI local para las evidencias de HU-02

El registro oficial del proyecto es **CNCF Distribution 3.0** en el host `nexus` de AWS
(`REGISTRY_BACKEND=distribution`, TLS + htpasswd, usuario `ci`; ver
[`docs/arquitectura/registro-artefactos.md`](../../docs/arquitectura/registro-artefactos.md)). Nexus
sigue instalado, pero el equipo decidió no aceptar su EULA.

Este `registry:2.8.3` local es un **registro equivalente solo para evidencias locales** de HU-02:
implementa la API OCI Distribution estándar y permite construir/publicar sin AWS.

> Escucha solo en `127.0.0.1`, no tiene autenticación y **no es para producción**. En los servidores
> de ambiente se usa el registro Distribution en `<ip-privada-nexus>:8082`.

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

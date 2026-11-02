# Compose por ambiente (HU-02)

| Archivo | Uso |
|---|---|
| `docker-compose.common.yml` | Stack completo: middleware, 8 servicios, cliente web, healthchecks, volúmenes y red |
| `docker-compose.dev.yml` | Override de dev: publica middleware y web en `127.0.0.1` |
| `docker-compose.stage.yml` | Override de stage: publica solo el cliente web |
| `docker-compose.prod.yml` | Override de prod: publica solo el cliente web (loopback por defecto) |
| `dev.env`, `stage.env`, `prod.env` | Valores no secretos por ambiente |

El stack no se ejecuta con un solo archivo: se combinan el común y el del ambiente.

```bash
docker compose --env-file deploy/compose/dev.env \
  --env-file "$HOME/.circleguard/dev.env" \
  --env-file "$HOME/.circleguard/dev-app.env" \
  -f deploy/compose/docker-compose.common.yml \
  -f deploy/compose/docker-compose.dev.yml up -d --wait
```

O con los scripts portables:

```bash
./deploy/compose-up.sh dev
./deploy/compose-down.sh dev
```

## Variables obligatorias

`stage.env` y `prod.env` dejan `IMAGE_REGISTRY` e `IMAGE_TAG` vacíos. Compose falla con
`required variable ... is missing a value` hasta que el despliegue los proporcione:

```bash
IMAGE_REGISTRY=nexus.example:8082 IMAGE_TAG=1.0.0 \
CG_ENV_FILE=/opt/circleguard/stage/.env ./deploy/compose-up.sh stage
```

## Puertos

| Ambiente | Web | Middleware | Servicios |
|---|---|---|---|
| dev | `127.0.0.1:3000` | `127.0.0.1`: 5432, 7474, 7687, 9092, 6379, 389, 636 | Solo por la red interna y el proxy `/auth`, `/identity`, ... |
| stage | `0.0.0.0:3000` | No publicado | Solo por la red interna |
| prod | `127.0.0.1:3000` | No publicado | Solo por la red interna |

En dev, `notification` no publica el 8082 para no chocar con el conector Docker de Nexus.

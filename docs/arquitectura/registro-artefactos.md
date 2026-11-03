# Registro de artefactos de CircleGuard (HU-01): decisión y trade-offs

Fecha: 2026-11-03. Estado: **decisión del equipo adoptada (`REGISTRY_BACKEND=distribution`),
implementada y probada en local; pendiente de desplegar en AWS** (requiere autorización).

## Problema

E1.2 pide «el registro de artefactos (Nexus o equivalente)» y HU-01 nombra Nexus. Nexus Repository
Community Edition 3.96.5 está desplegado en `circleguard-nexus`, pero no sirve componentes mientras
no se acepte su EULA, que es una decisión del equipo todavía pendiente
([evidencia 16](../evidencias/hu-01/16-nexus-eula.md)). Sin registro, E1.3 no puede publicar
imágenes y C1 no puede cerrarse.

## Alternativas evaluadas

| Opción | Licencia | Docker | Recursos | Autenticación y autorización | Etiquetas inmutables | Integración con la topología B | Coste adicional |
|---|---|---|---|---|---|---|---|
| Nexus CE 3.96.5 (actual) | EULA de Sonatype (pendiente) | Sí (conector 8082) | 4-6.4 GiB | Usuarios y roles | Sí (`allow_once`) | Ya desplegado | 0 |
| **CNCF Distribution 3.0.0** | Apache 2.0, sin EULA | Implementación de referencia del protocolo | ≈ 20-50 MiB | Usuarios htpasswd (bcrypt); **sin permisos por usuario** | No | Mismo host `nexus`, puerto 8082 ya permitido por los grupos de seguridad; sin cambios de IAM ni de red | 0 |
| Harbor | Apache 2.0 | Sí | ≈ 8 contenedores, 4 GiB o más recomendados | RBAC por proyecto | Sí | No cabe junto a Nexus en 8 GiB: exigiría otra instancia (cuota de 5 vCPU agotada) | Otra instancia |
| Zot | Apache 2.0 | OCI nativo; los manifiestos Docker necesitan una opción de compatibilidad | Bajo | htpasswd con políticas por usuario | Parcial | Mismo host | 0 |
| GitHub Container Registry | Servicio externo | Sí | — | Tokens personales | No | No es un servidor aprovisionado por scripts (E1.2) | Cuotas del plan |
| Amazon ECR | Servicio gestionado | Sí | — | IAM | Sí | Nuevos permisos IAM; no es un servidor Bash/Compose | Por GB |
| Nexus OSS ≤ 3.76 (EPL) | EPL | Sí | Igual que Nexus | Usuarios y roles | Sí | Mismo host | 0, pero **sin mantenimiento**: riesgo de seguridad |

## Decisión (adoptada por el equipo el 2026-11-03)

**CNCF Distribution es el registro Docker principal.** Nexus sigue instalado, con el EULA sin
aceptar, y nada depende de él para publicar ni descargar imágenes.

- `REGISTRY_BACKEND=distribution` (en `infra/config/aws.env`) despliega el stack
  `infra/bootstrap/registry/` en el host `nexus`, en el puerto del registro (8082). Nexus sigue
  desplegado con su interfaz en 8081 y su conector Docker, sin uso, pasa a `127.0.0.1:18082`.
- `REGISTRY_BACKEND=nexus` restaura el diseño original: el conector de Nexus publica el 8082 y el
  stack de Distribution no se despliega. Solo tiene sentido con `NEXUS_ACCEPT_EULA=true`.
- El cambio de una opción a otra **no migra imágenes**: habría que volver a publicarlas.

## Consecuencias y riesgos

| Aspecto | Consecuencia | Mitigación |
|---|---|---|
| Literalidad de HU-01 | HU-01 nombra Nexus; E1.2 admite «o equivalente» | Nexus sigue desplegado; la decisión del EULA permanece abierta y el cambio es una línea de configuración |
| Autorización | Todo usuario autenticado puede publicar y descargar | Solo existe el usuario `ci` (Jenkins). Las credenciales de solo descarga de los ambientes se definirán con E1.5 |
| Inmutabilidad | Distribution permite sobrescribir etiquetas | E1.3 exige versión semántica y nunca `latest`; el pipeline no debe reutilizar etiquetas |
| Transporte | TLS con un certificado autofirmado generado en el host. Los clientes Docker de la VPC confían en el registro por estar en `insecure-registries` (limitado a la subred `tools`): **cifrado sin autenticación del servidor** | El 8082 solo admite tráfico desde `ci` y los ambientes (grupos de seguridad) y no está expuesto a Internet. Mejora futura: una CA propia distribuida a los clientes |
| Limpieza | La recolección de basura es manual (`registry garbage-collect`) | Volumen holgado (25 GiB); documentado |
| Recursos | ≈ 50 MiB adicionales en un host de 8 GiB | Medible con `verify-infra.sh --health` |

## Integración con Jenkins

- **Cliente de Jenkins:** la imagen de Jenkins incluye `crane` (go-containerregistry v0.22.1,
  Apache 2.0, sha256 verificado). Con él, Jenkins publica y descarga sin el socket de Docker del
  host.
- **Credenciales:** el contenedor recibe `REGISTRY_ADDRESS` (IP privada de `nexus`:8082),
  `REGISTRY_CI_USER` y `REGISTRY_CI_PASSWORD` desde SSM, a través de su `.env` 0600.
- **Prueba:** `verify-infra.sh --registry` publica y descarga desde el host `ci` (Docker) y desde el
  contenedor de Jenkins (`crane`), y compara el digest con el de origen.
- **Rotación:** `infra/rotate-registry-password.sh` cambia el secreto, reescribe el usuario del
  registro y recrea Jenkins. Comprueba que la contraseña anterior deja de servir y restaura la
  anterior si falla el registro.

## Evidencia y estado

- **En local (2026-11-03):** `docs/evidencias/hu-01/auditoria/20261103T041534Z-integracion-local-hu01.txt`,
  22/22. Cubre:
  - el registro con TLS y autenticación;
  - la segunda ejecución de `bootstrap-registry.sh` sin cambios;
  - la publicación y descarga desde el host y desde la imagen de Jenkins;
  - la rotación, con la contraseña anterior rechazada;
  - la persistencia tras reiniciar y recrear el contenedor.
- **En AWS:** pendiente. Una ejecución autorizada de `infra/test-idempotency.sh --apply --approve
  ci,nexus` despliega el registro y ejecuta `verify-infra.sh --registry`. Hasta entonces C1 queda
  **BLOCKED** por esa autorización.

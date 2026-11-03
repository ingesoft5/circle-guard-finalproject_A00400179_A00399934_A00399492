# 18 · Mejoras técnicas para cerrar HU-01 (2026-11-03): preparadas y validadas en local, sin desplegar en AWS

> **Nota posterior (2026-11-03, 04:30 UTC):** esta evidencia queda superada por el
> [informe final](INFORME_FINAL_HU01_SPRINT1.md).
> - El equipo adoptó `REGISTRY_BACKEND=distribution` y los servidores de ambiente
>   (`ENV_SERVERS=dev,stage,prod`, `t3.small`, por pares).
> - Se añadieron la integración Jenkins → registro (`crane`), la rotación de la contraseña, la
>   guarda de cuota, la prueba de aislamiento y la recuperación tras reiniciar contenedores.
> - Los estados pasan a PASS, PARTIAL, FAIL y BLOCKED: C1, C2, C3 y C5 están en BLOCKED por la
>   autorización de AWS.

Base: commit `889ce09` más cambios locales sin confirmar.
- No se hizo ninguna llamada a AWS ni se ejecutó ningún *bootstrap* con `--apply`.
- El EULA de Nexus sigue sin aceptar.
- No se modificó IAM, SSM, EBS ni la red.

Las clasificaciones **no cambian**: lo preparado aquí solo pasará a PASS cuando exista evidencia en
AWS.

## 1. Estado de los criterios

| Criterio | Antes | Ahora | Qué se hizo | Qué falta para PASS |
|---|---|---|---|---|
| C1 | PARTIAL | **PARTIAL** | Registro Docker CNCF Distribution (Apache 2.0, sin EULA) en el servidor `nexus`, puerto 8082, con TLS y el usuario `ci`; Nexus se conserva ([decisión](../../arquitectura/registro-artefactos.md)). Prueba local: 21/21 | Confirmación del equipo de `REGISTRY_BACKEND=distribution`, una ejecución autorizada en AWS y `verify-infra.sh --registry` en PASS (publicar y descargar desde `ci`) |
| C2 | PARTIAL | **PARTIAL** | Servidores de ambiente opcionales (`ENV_SERVERS`) con su host, `.env` y pruebas de tráfico (`--isolation`); corregido el *bootstrap* de ambiente, que no programaba la parada automática | Decisiones de cuota (10 vCPU frente a 5), presupuesto y tamaño, o aceptación del alcance de red; después, `verify-infra.sh --isolation` con tráfico entre ambientes |
| C3 | PARTIAL | **PARTIAL** | `infra/test-idempotency.sh` automatiza la evidencia 15 (tres *snapshots*, dos ejecuciones, persistencia, registro, copias enmascaradas y parada obligatoria). El *snapshot* incluye la configuración del host | Ejecutar `test-idempotency.sh --apply --approve ci,nexus` con autorización (≈ 0.12-0.21 USD) |
| C4 | PASS | **PASS** | Revisión sin hallazgos nuevos | — |
| C5 | PARTIAL | **PARTIAL** | Ensayo de reconstrucción documentado en dos niveles y tabla de pasos humanos con su motivo ([infra/README.md](../../../infra/README.md#ensayo-de-reconstrucción-desde-cero)); orden del comando único revisado | Ejecutar el ensayo (nivel 1: otra persona y otra estación de trabajo) y el registro en AWS |
| C6 | PASS | **PASS** | El usuario del registro se guarda en SSM; su contraseña llega a htpasswd, `curl` y `docker login` siempre por stdin; la prueba de publicación usa una configuración de Docker temporal que se borra al terminar | — |

## 2. Cambios en el repositorio

| Archivo | Problema | Cambio |
|---|---|---|
| `docs/arquitectura/registro-artefactos.md` (nuevo) | No había alternativa documentada al EULA | Siete opciones comparadas, decisión, riesgos y condiciones de cierre |
| `infra/bootstrap/registry/` (nuevo: `docker-compose.yml`, `config.yml`, `prepare.sh`, `configure.sh`) | Sin registro funcional | Stack de Distribution 3.0.0 con *healthcheck*. `prepare.sh` comprueba el puerto y genera el certificado (EC P-256, 10 años) y el usuario bcrypt **antes** de arrancar el contenedor, y lo reinicia si cambian. `configure.sh` comprueba 401 sin credenciales y 200 con `ci` |
| `infra/bootstrap-registry.sh` (nuevo) | — | Despliega el registro; con `REGISTRY_BACKEND=nexus` lo retira sin borrar su volumen |
| `infra/bootstrap-nexus.sh`, `infra/bootstrap/nexus/docker-compose.yml` | El conector de Nexus ocupaba el 8082 aunque no sirviera | Con `distribution`, el conector solo escucha en `127.0.0.1:18082` |
| `infra/bootstrap/host/setup-docker.sh` | Los clientes Docker no podían usar un registro privado de la VPC | `insecure-registries` limitado a la subred `tools`, igual en todos los hosts; sin CIDR, el archivo es idéntico al desplegado |
| `infra/bootstrap/lib/remote.sh` | — | Pasa el CIDR y ejecuta el `prepare.sh` opcional de cada stack antes de `docker compose up` |
| `infra/bootstrap/lib/aws.sh`, `lib/common.sh` | `CG_ROLES=(ci nexus)` fijo: ningún script podía crear servidores de ambiente | Roles según `ENV_SERVERS`; validación de `ENV_SERVERS` y `REGISTRY_BACKEND`; vCPU por tipo; orden de las herramientas del servidor `nexus` |
| `infra/bootstrap-env.sh` | **Defecto:** no pasaba las horas de parada ni el swap; un host de ambiente quedaría sin parada automática | Mismos parámetros que los servidores de herramientas |
| `infra/bootstrap-servers.sh` | Aprobar un rol no configurado no hacía nada, sin avisar; no se veía la necesidad de vCPU | Rechaza roles no configurados; muestra las vCPU necesarias frente a `QUOTA_VCPU_TARGET` |
| `infra/bootstrap-all.sh` | No conocía el registro ni los ambientes opcionales | Orden que libera y después ocupa el 8082; ambientes de `ENV_SERVERS` |
| `infra/verify-infra.sh` | Sin comprobaciones del registro; el *snapshot* no cubría la configuración del host | Comprobaciones del registro en `--health` (salud, 401, 200, no expuesto; el último con `-k` para no dar un falso PASS). Nuevo `--registry` (publicar y descargar). Flujo `ci → nexus:8082`. `.env` del registro en `--credentials`. Líneas `hostfile` en el *snapshot* |
| `infra/test-idempotency.sh` (nuevo) | La evidencia 15 era un procedimiento manual | Prueba automatizada con parada garantizada (`trap EXIT`) y límite de 50 min |
| `infra/config/aws.env`, `secrets.catalog` | — | `REGISTRY_BACKEND`, `ENV_SERVERS`, `NEXUS_DOCKER_STANDBY_PORT`; secreto `tools/registry/REGISTRY_CI_PASSWORD` |
| `infra/bootstrap-quota.sh` | El comentario hablaba de seis servidores y 12 vCPU | Comentario corregido |
| `infra/README.md`, `docs/arquitectura/infra-ambientes.md` | — | Registro, ambientes opcionales con su costo y cuota, prueba automatizada, ensayo de reconstrucción y pasos humanos |
| Evidencias 15, 16 y 17, y el README de evidencias | — | Notas posteriores fechadas |

IAM no cambia: no se usa ninguna acción nueva de AWS. El registro y la prueba de publicación solo
usan Docker y SSH.

## 3. Validaciones ejecutadas (resultados reales)

| Validación | Resultado |
|---|---|
| `bash -n` sobre los 30 scripts de `infra/` | 0 errores |
| ShellCheck v0.11.0 (`sha256:61862eba…25a8d`), `-x -S style`, 30 scripts ([`auditoria/20261103T030812Z-shellcheck-hu01.txt`](auditoria/20261103T030812Z-shellcheck-hu01.txt)) | `{"comments":[]}`; el control positivo detecta SC2086. El reporte lista el sha256 de los 30 scripts, los 10 modificados y los 4 nuevos respecto a `889ce09`. La copia solo se diferencia del original (`infra/security/reports/`, sha256 `df5cff17…`) en los espacios finales. **El reporte de `fase4/` solo certifica los scripts de `3632068`** |
| Prueba local funcional del registro en Docker Desktop ([`auditoria/20261103T030223Z-prueba-local-registro.txt`](auditoria/20261103T030223Z-prueba-local-registro.txt)) | **21 PASS, 0 FAIL**. Detalle abajo |
| Gitleaks v8.30.1 sobre el árbol de trabajo, con todos los archivos nuevos (403 archivos; [`auditoria/20261103T031153Z-worktree-summary.txt`](auditoria/20261103T031153Z-worktree-summary.txt)) | **ACTIVO=0**, PRUEBA=9, RESIDUAL=2: los mismos hallazgos de antes, ninguno nuevo. La copia se diferencia del original (sha256 `27f2f910…`) solo en el fin de línea |
| Comprobaciones unitarias ([`auditoria/20261103T030223Z-comprobaciones-unitarias-hu01.txt`](auditoria/20261103T030223Z-comprobaciones-unitarias-hu01.txt)) | **24 PASS, 0 FAIL**. Detalle abajo |

Comprobaciones de la prueba local del registro:
- `prepare.sh` es idempotente: los hashes del certificado, la llave y el htpasswd no cambian en la
  segunda ejecución.
- bcrypt, y la contraseña no aparece en claro.
- Contenedor `healthy` y solo TLS.
- 401 sin credenciales, con una contraseña incorrecta o con un usuario inexistente; 200 con `ci`.
- `bootstrap-registry.sh --plan` ve el stack convergido.
- `verify-infra.sh --health` y `--registry` en PASS: publicación y descarga reales.
- Rotación de la contraseña.
- Detección del puerto ocupado sin crear nada.

Comprobaciones unitarias:
- roles y validaciones;
- orden del 8082;
- vCPU;
- `daemon.json` idéntico sin CIDR;
- puertos de Compose en los dos modos;
- `test-idempotency.sh --plan`.

**Limitaciones de estas pruebas:**
- Son locales (Docker Desktop en Windows), no en AWS.
- No ejercitan el SSH ni la red de la VPC, ni el `daemon.json` con `insecure-registries` en un
  host Ubuntu.
- `bootstrap-all.sh`, `bootstrap-servers.sh` con `ENV_SERVERS` y `test-idempotency.sh --apply`
  necesitan AWS y no se ejecutaron.

## 4. Pruebas pendientes y quién decide

| Prueba o decisión | Necesita | Coste estimado |
|---|---|---|
| Confirmar `REGISTRY_BACKEND=distribution` (o mantener Nexus y decidir el EULA) | Equipo | 0 |
| `test-idempotency.sh --apply --approve ci,nexus`: despliega el registro, prueba C3, la persistencia y la publicación | Autorización para arrancar las instancias y, si cambió la IP del operador, para actualizar la regla del 22 | ≈ 0.12-0.21 USD |
| Servidores de ambiente | Equipo: cuota de 10 vCPU (solicitud gratuita; la aprobación en el plan gratuito no está comprobada), presupuesto (≈ 18 USD en el escenario conservador, por encima de 15) y tamaño | Ver `infra/README.md` |
| Ensayo de reconstrucción (nivel 1 o 2) | Otra persona del equipo; el nivel 2 además destruye datos | Nivel 1 ≈ 0.12-0.21 USD |
| Captura de pantalla del escaneo de secretos (evidencia 4) | Equipo | 0 |

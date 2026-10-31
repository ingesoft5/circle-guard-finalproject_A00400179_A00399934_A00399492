# Revisión de idempotencia de todos los scripts de HU-01

Criterio 3: ejecutar los scripts dos veces no cambia el resultado. Para cada recurso se indica cómo
se detecta el estado real, qué se hace si falta, cómo se corrige si se desvió y con qué evidencia
se demostró.

**Leyenda de la columna "Demostrado":** ✅ ejecutado dos veces con `created=0 updated=0` en la
segunda · 🔎 revisión estática del código, a demostrar en AWS (Etapa 4) · ➖ no aplica (script de
solo lectura).

| Script | Recurso o acción | Detección del estado | Si falta | Si se desvió | Demostrado |
|---|---|---|---|---|---|
| `bootstrap-network.sh` | VPC | Etiquetas `Project` + `Name`; **se detiene ante duplicados** (`cg_one`) | `create-vpc` con etiquetas | CIDR distinto: se detiene sin tocar la VPC; nombres DNS: se activan | 🔎 |
| | Internet gateway | Etiquetas; VPC adjunta | Crear y adjuntar | Adjunto a otra VPC: se detiene | 🔎 |
| | 4 subredes | Etiquetas; CIDR y zona | Crear | CIDR o zona distintos: se detiene; IPv4 al lanzar: se activa | 🔎 |
| | Tabla de rutas | Etiquetas; ruta `0.0.0.0/0`; asociaciones | Crear, ruta y asociar | Ruta hacia otro destino: `replace-route` | 🔎 |
| | 6 grupos de seguridad y sus reglas | Etiquetas; `describe-security-group-rules` | Crear y autorizar | **Reconciliación completa**: añade las que faltan y revoca cualquier regla no deseada (incluida la de salida por defecto y las IP de operador antiguas) | 🔎 |
| `bootstrap-secrets.sh` | Secretos SSM | `get-parameter` (distingue `ParameterNotFound` de otros errores) | Generar y `put-parameter` **sin** `--overwrite` | Nunca se sobrescriben ni se rotan | ✅ (backend local) · 🔎 (SSM) |
| | Llaves SSH | Archivo local, copia en SSM, par en EC2 | Generar, custodiar e importar | Falta la privada local: se restaura desde SSM; huella distinta: aviso | 🔎 |
| `bootstrap-servers.sh` | 6 instancias EC2 | Etiquetas `Project` + `Role`, en estados distintos de *terminated*; **se detiene si hay más de una** | `run-instances` con `--client-token` (evita duplicados al reintentar) | Detenida: se inicia **solo** con `--approve`; tipo distinto: aviso, sin redimensionar; créditos de CPU o IMDS: se corrigen | 🔎 |
| `setup-docker.sh` (en el host) | Docker y Compose | `dpkg-query` | Instalar desde el repositorio oficial | — | 🔎 |
| | `daemon.json` y `vm.max_map_count` | `cmp` y `sysctl -n` | Escribir y aplicar | Reinicia Docker **solo** si el archivo cambió; el kernel solo se sube, nunca se baja | 🔎 |
| `bootstrap-{jenkins,sonarqube,nexus}.sh` | Archivos del stack | sha256 local frente al remoto | Publicar | Reescribir solo si difiere | ✅ |
| | `.env` (secretos) | sha256 y **permisos 0600** | Escribir con `umask 077` | Contenido distinto: reescribir; permisos distintos: `chmod 600` (deriva provocada y corregida) | ✅ |
| | Contenedores | Nombre, ID y **estado** de cada contenedor del proyecto Compose | `docker compose up -d` | Imagen reconstruida **solo** si cambió el contexto de *build*; contenedor detenido: se inicia y se informa `UPDATED` | ✅ |
| | Configuración de la herramienta | API de cada herramienta (comprobar y luego actuar) | Contraseña gestionada, repositorio, *realm*, acceso anónimo | Deriva manual del administrador: se detiene y lo informa | ✅ Jenkins y SonarQube · ⏳ Nexus (EULA) |
| `bootstrap-env.sh` | `.env` del ambiente | sha256 y permisos 0600 | Escribir | Igual que arriba; directorios de otros ambientes en el host: se detiene | 🔎 |
| `bootstrap-all.sh` | Orquestación | Suma de contadores de cada paso | — | Se detiene en el primer error; se reanuda volviendo a ejecutarlo | 🔎 |
| `teardown.sh` | Detener o destruir | Etiquetas `Project` + `ManagedBy` | — | Lo que ya no existe se omite; un stack ya detenido figura como `UNCHANGED` | ✅ (local) · 🔎 (AWS) |
| `verify-infra.sh`, `scan-secrets.sh`, `tunnel.sh` | Lectura o acceso | — | — | — | ➖ |

## Defectos de idempotencia encontrados y corregidos

| # | Defecto | Corrección |
|---|---|---|
| 1 | `docker compose up --build` recreaba Jenkins en cada ejecución (BuildKit genera un digest nuevo en cada *build*) | Se reconstruye solo si cambió el contexto |
| 2 | `CG_JENKINS_URL` usaba la IP pública, que cambia tras detener e iniciar la instancia, y recreaba el contenedor | La URL es la del túnel SSH (`http://localhost:8080/`) |
| 3 | Las búsquedas por etiqueta tomaban el primer recurso si había duplicados | `cg_one` se detiene y lo informa |
| 4 | Un cambio de permisos de un `.env` no se detectaba | Se compara y restaura 0600 |
| 5 | Iniciar un contenedor detenido se informaba como `UNCHANGED` | Se compara también el estado |
| 6 | `teardown --target local --stop` informaba `UPDATED` sobre stacks ya detenidos | Ahora informa `UNCHANGED` |

## Pendiente de demostrar en AWS (Etapa 4, con autorización de costos)

`bootstrap-all.sh --apply --approve all` dos veces, `verify-infra.sh --snapshot` antes y después
(con `diff` vacío) y `teardown.sh --destroy` seguido de una reconstrucción.

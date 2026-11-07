# Decisiones asistidas por IAG

Registro de decisiones de arquitectura e ingeniería tomadas con apoyo de la IA. Cada entrada
indica el contexto, las alternativas consideradas y las consecuencias. Las decisiones se
numeran y no se reescriben: si cambian, se añade una nueva entrada.

---

## D-01 · Estrategia de ramas y destino del PR

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada

**Contexto.** `main` solo tiene el commit inicial; `origin/dev` y
`origin/HU-02_Imágenes-Docker-inmutables` apuntan al mismo commit que
`origin/HU01_Infraestructura_nube_bash` (`3632068`). No existía ningún PR abierto.

**Decisión.** El PR de HU-02 se hace **desde `HU-02_Imágenes-Docker-inmutables` hacia `dev`**.
Cuando `dev` tenga el merge, se crea la rama de HU-06 **desde ese nuevo `dev`**.

**Alternativas.** PR de HU-02 hacia `main` (arrastraría los 12 commits de HU-01 mientras no se
integre); PR apilado contra la rama de HU-01 (más frágil al cerrar la primera).

**Consecuencias.** Como `dev` ya contiene HU-01, el PR de HU-02 mostrará solo sus propios commits.
HU-01 debe integrarse a `dev`/`main` por su cuenta; no es un prerrequisito del PR de HU-02.

---

## D-02 · Portabilidad: WSL es solo el equipo de desarrollo

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada

**Contexto.** El equipo trabaja en Windows con WSL, pero el producto debe desplegarse en 7
computadoras y en los hosts de ambiente (Linux).

**Decisión.** Los scripts son **Bash portable** y no usan rutas de WSL, PowerShell ni supuestos de
Windows. Requisitos: Docker Engine/Desktop con Compose v2.20+ y Bash. En el equipo de desarrollo se
puede usar WSL; en los hosts, Linux.

**Alternativas.** Scripts específicos para WSL (no portables); scripts de PowerShell (no funcionan
en los hosts Linux).

**Consecuencias.** `deploy/*.sh` se prueban con `bash -n` y se documentan para WSL, Linux y Git
Bash. Las rutas de secretos se pasan por variables (`CG_ENV_FILE`, `CG_APP_ENV_FILE`). El registro
local escucha en `127.0.0.1` y no se expone.

---

## D-03 · EULA de Nexus: se deja pendiente y se usa un registro equivalente

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada (decisión del equipo)

**Contexto.** Nexus Community Edition exige aceptar el EULA de Sonatype antes de permitir
descargar o subir componentes. HU-01 lo deja en `NEXUS_ACCEPT_EULA=false` y el bootstrap reporta
`PLAN`. Sin EULA no se crea el repositorio `circleguard-docker` ni se puede publicar.

**Decisión.** **No se acepta el EULA todavía.** Para evidenciar la publicación se usa
`deploy/registry/` con `registry:2.8.3` (API OCI estándar) en `127.0.0.1:5000`, sin autenticación
y solo para evidencias. Nexus sigue siendo el registro oficial y su configuración declarativa
(`writePolicy: allow_once`) queda lista para cuando el equipo acepte.

**Alternativas.** Aceptar el EULA ahora (decisión legal/del equipo, no técnica); usar el
`admin` de Nexus (mala práctica); no evidenciar la publicación (incumple el criterio).

**Consecuencias.** La evidencia se etiqueta como "registro equivalente". El día que se acepte el
EULA hay que crear usuarios de push/pull en Nexus y volver a publicar con
`IMAGE_REGISTRY=<nexus>:8082`. El EULA es un acuerdo de licencia, no un bug: mientras esté
pendiente, Nexus no acepta artefactos.

---

## D-04 · No modificar el código base

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada

**Contexto.** El equipo pidió expresamente no tocar el código base en esta historia.

**Decisión.**
- Los servicios se conectan al middleware con variables `SPRING_*` desde Compose; no se editan
  `application.yml` ni el Gradle.
- No se añade Actuator.
- El cliente web se adapta **dentro del Dockerfile**: `sed` reescribe las URLs
  `http://localhost:<puerto>` por rutas del mismo origen (`/auth`, `/identity`, ...). El
  repositorio no cambia; la imagen resultante es agnóstica al host.
- No se versiona `gradle/wrapper/gradle-wrapper.jar`: el builder usa la imagen
  `gradle:8.14-jdk21`, que fija la misma versión que el wrapper.

**Alternativas.** Editar los YAML y `Config.ts` (más limpio a largo plazo, pero prohibido en esta
historia); usar `latest` o tags flotantes (prohibido por el criterio).

**Consecuencias.** Los healthchecks son sondas HTTP, no Actuator. La reproducibilidad byte a byte
de los JAR queda pendiente. El cambio de URLs del web es una transformación de build documentada.

---

## D-05 · Compose: base común + tres overrides

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada

**Contexto.** El criterio pide "un archivo Docker Compose por cada ambiente" y el proyecto
sugiere `deploy/{compose,k8s}/`.

**Decisión.** `docker-compose.common.yml` contiene el stack completo y los healthchecks;
`docker-compose.dev.yml`, `.stage.yml` y `.prod.yml` contienen solo las diferencias (puertos,
límites, política de reinicio). El despliegue combina `common + <env>`.

**Alternativas.** Tres archivos autónomos (duplicación y deriva); un único archivo con perfiles
(no cumple "un archivo por ambiente").

**Consecuencias.** Hay un archivo por ambiente y una sola fuente de verdad para los servicios.
`deploy/compose-up.sh <env>` construye la invocación y valida los archivos.

---

## D-06 · Healthchecks sin Actuator

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada (con limitación)

**Contexto.** Los 8 servicios no tienen `spring-boot-starter-actuator` y no se puede tocar el
código base.

**Decisión.** Sondas HTTP a `/` que aceptan `2xx`, `3xx`, `400`, `401`, `403` y `404`; el
middleware usa sus herramientas nativas. `web` espera a los 8 servicios `healthy`.

**Alternativas.** Añadir Actuator (mejor, pero toca el código base); comprobar solo el puerto TCP
(más débil); no poner healthchecks (incumple el criterio).

**Consecuencias.** La sonda demuestra que el proceso acepta HTTP, no que sus dependencias estén
sanas. Se documenta como limitación y se recomienda Actuator en una historia posterior.

---

## D-07 · Versionado semántico obligatorio y bases fijadas por digest

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada

**Contexto.** El criterio prohíbe `latest` y pide imágenes reproducibles.

**Decisión.** `deploy/lib.sh` valida `MAJOR.MINOR.PATCH` y rechaza `latest` antes de Docker. Cada
imagen lleva etiquetas OCI (`version`, `revision`, `created`, `source`). Las bases se fijan con
`tag@sha256` y el cliente web instala con `npm ci`.

**Alternativas.** Tags flotantes (no reproducibles); versión manual sin validación (riesgo de
`latest`).

**Consecuencias.** `stage.env` y `prod.env` dejan `IMAGE_TAG` vacío: Compose falla en vez de usar
un tag flotante. La reproducibilidad byte a byte de los JAR sigue pendiente (timestamps de Gradle).

---

## D-08 · Nombres y registro de las imágenes

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada

**Decisión.**

```
${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/circleguard-<servicio>:<semver>
${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/circleguard-web:<semver>
```

`IMAGE_NAMESPACE` por defecto es `circleguard`. Para Nexus, `IMAGE_REGISTRY=<host>:8082`.

**Consecuencias.** El mismo nombre funciona en `registry:2` y en el repositorio Docker de Nexus.
El repositorio Nexus usa `allow_once`, así que un tag publicado no se puede sobrescribir.

---

## D-09 · Evidencias diferidas hasta tener Docker

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada

**Contexto.** No hay Docker en Windows ni en WSL; tampoco servidores de ambiente creados.

**Decisión.** Se implementan y validan estáticamente los archivos; las salidas reales de
`docker build`, `docker inspect`, el catálogo del registro y los healthchecks se generan cuando
Docker esté instalado. `docs/evidencias/hu-02/README.md` deja los comandos exactos.

**Consecuencias.** La historia no se considera cerrada hasta capturar esas salidas. No se
inventan evidencias.

---

## D-10 · Registro local sin autenticación y solo en loopback

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada (temporal)

**Contexto.** `registry:2` se usa solo para evidencias, no para producción.

**Decisión.** Publicar en `127.0.0.1:5000`, sin TLS ni autenticación. El registro oficial
(Nexus) usará autenticación y usuarios de push/pull.

**Consecuencias.** No debe exponerse a la red. Si se necesita en otra máquina, se accede por túnel
SSH o se usa Nexus.

---

## D-11 · Prod con el web en loopback hasta E2.6

- **Fecha:** 2026-11-02
- **Historia:** HU-02
- **Estado:** Aceptada

**Contexto.** No hay TLS/ingress y el criterio de HU-02 no lo incluye.

**Decisión.** En `prod`, el cliente web se publica en `127.0.0.1:3000`. El acceso será por túnel
SSH o por un proxy inverso con TLS que llegará en E2.6.

**Consecuencias.** Prod no queda abierto a Internet. La usabilidad final depende del ingress de
la siguiente entrega.

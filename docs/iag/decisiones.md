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

---

## D-12 · Pipeline de HU-06 en código, independiente de AWS

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada

**Contexto.** No hay Jenkins con plugins, ni Docker en el equipo de desarrollo, ni hosts de
ambiente con capacidad para el stack completo.

**Decisión.** Implementar el `Jenkinsfile` y los scripts de `deploy/` como código portable, con
modos `local` y `ssh`, parámetros para construir/publicar imágenes y un destino de despliegue
configurable. La ejecución end-to-end se hará cuando HU-04 y los hosts estén listos.

**Alternativas.** Esperar a tener AWS/Jenkins para escribir el pipeline (pierde tiempo); simular
las evidencias (no es aceptable).

**Consecuencias.** El pipeline se puede revisar y probar por partes. Las evidencias de ejecución
quedan pendientes y deben capturarse antes de cerrar HU-06.

---

## D-13 · Mapeo de ramas dev y main

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada

**Contexto.** HU-06 dice “merge a `main`”, pero el equipo integra en `dev` y publica desde `main`.

**Decisión.** `dev` despliega dev y stage automáticamente; `main` añade la aprobación manual, prod y
el tag. `FORCE_PROD=true` permite probar el flujo desde otra rama.

**Consecuencias.** El flujo respeta la rama de integración del equipo y el criterio de aprobación
antes de prod. Las evidencias deben mostrar una ejecución en `dev` y otra en `main`.

---

## D-14 · `pollSCM` en lugar de webhook

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada (temporal)

**Contexto.** Jenkins solo escucha en `127.0.0.1`; GitHub no puede llamarlo. HU-01 advierte que un
webhook exige TLS o un relé.

**Decisión.** Usar `pollSCM('H/5 * * * *')`. Cuando exista TLS/relé (E2.6/HU-04), cambiar a
webhook.

**Consecuencias.** El despliegue ocurre en ≤ 5 minutos, no instantáneamente. Se documenta como
limitación.

---

## D-15 · Tests base no bloqueantes

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada (temporal)

**Contexto.** Los 10 fallos base de HU-01 (Testcontainers, seguridad de tests, middleware y JWT)
siguen existiendo y no son de HU-06.

**Decisión.** La etapa ejecuta `./gradlew test --continue`, publica JUnit y deja el build
`UNSTABLE` sin bloquear el despliegue. No se ocultan: se archivan y se notifican.

**Alternativas.** Bloquear todo el pipeline hasta corregirlos (impide avanzar HU-06); ignorarlos
(peor).

**Consecuencias.** El pipeline puede desplegar con un build `UNSTABLE`. HU-04/E1.6 debe corregir
los 10 tests y volver la etapa bloqueante.

---

## D-16 · Build y publicación de imágenes opcionales

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada

**Contexto.** `crane` publica y descarga, pero no construye; el Jenkins de HU-01 no tiene Docker ni
un agente de build.

**Decisión.** Parámetros `BUILD_IMAGES` y `PUBLISH_IMAGES` (por defecto `true`). Si el Jenkins no
tiene Docker, se pueden desactivar y usar imágenes ya publicadas; la construcción queda en HU-04.

**Consecuencias.** El pipeline se puede usar para promoción/rollback sin Docker en el controlador.
La evidencia de build de imágenes sigue siendo de HU-04.

---

## D-17 · Trazabilidad JSON + historial TSV

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada

**Decisión.** `deploy/releases/<env>.json` guarda la última versión (ambiente, versión, commit,
fecha, actor, evento) y `history.tsv` el historial append-only. Jenkins archiva ambos.

**Alternativas.** Solo un artefacto de Jenkins (se pierde al limpiar builds); una rama de releases
(más compleja).

**Consecuencias.** La trazabilidad es legible y versionable. Si se quiere fuente de verdad en Git,
el equipo puede hacer que Jenkins commitee los archivos.

---

## D-18 · Rollback reutiliza deploy y valida imágenes

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada

**Decisión.** `rollback.sh` rechaza la versión actual, verifica las 9 imágenes con
`docker manifest inspect`/`crane manifest` y llama a `deploy.sh` con evento `rollback`.

**Consecuencias.** No se redespliega una versión inexistente. La verificación remota se delega al
host cuando `DEPLOY_MODE=ssh`.

---

## D-19 · Notificaciones Discord/Slack no fatales

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada

**Decisión.** `notify.sh` usa `DISCORD_WEBHOOK_URL` o `SLACK_WEBHOOK_URL`; si no hay webhook o
falla el envío, informa y termina en 0. El pipeline lo llama en `post`.

**Consecuencias.** Un fallo de notificación no tumba un despliegue. La evidencia de la
notificación se captura por separado.

---

## D-20 · E2E de humo como gate de stage

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada (ampliable)

**Contexto.** No había pruebas E2E.

**Decisión.** `tests/e2e-playwright` verifica que el web responde y que `/healthz` está en 200.
`deploy/e2e.sh` es el gate antes de stage.

**Consecuencias.** Hay un gate real y ejecutable; la cobertura funcional (login, cuestionario, QR)
se amplía en la siguiente iteración.

---

## D-21 · Plantilla y política de cambio

> **Movida a HU-07.** La plantilla de solicitud de cambio, la política de aprobación y
> `.github/PULL_REQUEST_TEMPLATE.md` se desarrollan en la rama de HU-07 para no mezclar alcances.

---

## D-22 · Release notes desde Conventional Commits

> **Movida a HU-07.** `deploy/release-notes.sh`, `CHANGELOG.md` y `docs/release-notes/` se
> desarrollan en la rama de HU-07.

---

## D-23 · Wrapper de Gradle versionado

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Aceptada

**Contexto.** `*.jar` estaba ignorado y `gradle/wrapper/gradle-wrapper.jar` no se versionaba; un
clon limpio no podía ejecutar `./gradlew` y Jenkins no podía compilar.

**Decisión.** Versionar el wrapper de Gradle 8.14 (43 KiB, `GradleWrapperMain` verificado) con una
excepción en `.gitignore`, y normalizar `gradlew`/`Jenkinsfile` a LF.

**Consecuencias.** Jenkins y cualquier host con JDK 21 pueden ejecutar `./gradlew` sin instalar
Gradle. La imagen de build de HU-02 sigue usando `gradle:8.14-jdk21` para las imágenes.

---

## D-24 · Capacidad y cuota de ambientes pendientes

- **Fecha:** 2026-11-05
- **Historia:** HU-06
- **Estado:** Pendiente (decisión del equipo)

**Contexto.** HU-01 creó hosts `t3.small` (2 GiB) y `QUOTA_VCPU_LIMIT=5`. El stack completo tiene
15 contenedores; `ci` + `nexus` + un ambiente = 6 vCPU.

**Decisión.** No se fuerza un cambio de infraestructura en HU-06. El pipeline soporta `local` y
`ssh`; la evidencia real en AWS queda condicionada a:
1. redimensionar los hosts de ambiente (por ejemplo `m7i-flex.large`), y
2. subir `QUOTA_VCPU_LIMIT`/cuota (la cuenta tiene 16 vCPU reales).

**Consecuencias.** HU-06 puede validarse con Docker local, pero la demostración AWS completa
requiere aprobación de costo y cuota. Se documenta como bloqueo, no se simula.

---

## D-25 · El registro oficial pasa a CNCF Distribution

- **Fecha:** 2026-11-05
- **Historia:** HU-01 (impacto en HU-02/HU-06)
- **Estado:** Aceptada; reemplaza D-03 y D-10 en lo relativo a Nexus

**Contexto.** El equipo decidió el 2026-11-03 no aceptar el EULA de Nexus y usar CNCF Distribution
3.0 en el host `nexus` (`REGISTRY_BACKEND=distribution`, TLS + htpasswd, usuario `ci`).

**Decisión.** El registro de imágenes es Distribution; Nexus queda instalado sin uso. Para AWS,
`IMAGE_REGISTRY=<ip-privada-nexus>:8082`. `deploy/registry/` (`registry:2`) queda solo como
equivalente local de evidencias.

**Consecuencias.** La publicación ya no depende del EULA. Jenkins usa `crane` para publicar y
descargar sin el socket de Docker.

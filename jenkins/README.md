# Jenkins para HU-06

El `Jenkinsfile` de la raíz implementa el pipeline de HU-06/HU-07 y, desde la integración de HU-03,
reutiliza la Shared Library de `jenkins/vars`. `infra/bootstrap/jenkins/plugins.txt` ya instala el
conjunto de pipeline de HU-03; esta carpeta documenta los extras que necesita el CD (Node/Playwright
y SSH) y cómo completar la imagen.

## 1. Plugins

`infra/bootstrap/jenkins/plugins.txt` ya incluye el conjunto de pipeline de HU-03 (workflow, Git y
GitHub, credenciales, JUnit, Sonar, timestamper, ws-cleanup y build-timeout). `jenkins/plugins.txt`
añade lo propio del CD: `nodejs` y `ssh-credentials`/`ssh-agent`. Para aplicarlo:

1. Copiar las entradas que falten de `jenkins/plugins.txt` en `infra/bootstrap/jenkins/plugins.txt`
   (manteniendo `configuration-as-code`).
2. Cambiar el tag de la imagen en `infra/bootstrap/jenkins/docker-compose.yml`, por ejemplo:
   `circleguard-jenkins:2.580.2-lts-jdk21-casc2144-crane0.22.1-pipeline1`.
3. Reconstruir y recrear Jenkins:
   ```bash
   bash infra/bootstrap-jenkins.sh --apply
   ```
4. Verificar en **Manage Jenkins → Plugins** que no hay dependencias pendientes ni errores de
   compatibilidad. Fijar las versiones resueltas en `plugins.txt` para reproducibilidad.

> La imagen validada de HU-01 aún no tiene `nodejs` ni el plugin SSH; hasta reconstruirla, el E2E y
> el despliegue `DEPLOY_MODE=ssh` quedan bloqueados.
> Esa es la primera tarea de HU-04.

## 2. Credenciales (IDs exactos que usa el Jenkinsfile)

| ID | Tipo | Uso |
|---|---|---|
| `circleguard-registry` | Username/Password | `deploy/publish-images.sh` (usuario `ci` y contraseña del registro Distribution) |
| `github-token` | Secret text | `deploy/tag-release.sh` (push del tag `vX.Y.Z`) |
| `discord-webhook` | Secret text | `deploy/notify.sh` (fallos y estados) |
| `circleguard-deploy` | SSH username with private key | `DEPLOY_MODE=ssh` hacia los hosts de ambiente |

Crear las credenciales en **Manage Jenkins → Credentials → System → Global credentials**. No se
versionan valores.

## 3. Agente / herramientas

| Requisito | Cuándo |
|---|---|
| JDK 21 + Git + Bash | Siempre (build/tests con `./gradlew`) |
| Docker Engine + Compose | Si `BUILD_IMAGES=true` o `PUBLISH_IMAGES=true` |
| Node 22 + Playwright | Si el E2E corre en el agente (`nodejs` plugin o imagen de Playwright) |
| SSH + llave `circleguard-deploy` | Si `DEPLOY_MODE=ssh` |
| Repositorio en `DEPLOY_PATH` | El host de ambiente debe tener un clon del repo (HU-01 no lo clona) |
| `crane` | Ya está en la imagen de HU-01; sirve para publicar/descargar sin socket |

El `gradle/wrapper/gradle-wrapper.jar` ya está versionado, así que `./gradlew` funciona en un
clon limpio con JDK 21.

## 4. Trigger

HU-01 no expone Jenkins a Internet, así que GitHub no puede llamar a un webhook. El `Jenkinsfile`
usa `pollSCM('H/5 * * * *')`: detecta el merge en ≤ 5 minutos. Para webhook inmediato hace falta
TLS o un relé (E2.6/HU-04).

## 5. Job multibranch

1. **New Item → Multibranch Pipeline**.
2. Branch source: GitHub, repositorio
   `ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492`.
3. Credenciales: `github-token` o una GitHub App.
4. Build configuration: **by Jenkinsfile** (ruta `Jenkinsfile`).
5. Scan: cada 5 minutos (o webhook si se expone).
6. Ramas: `dev` y `main`; el resto solo compila/prueba.
7. Parámetros `E2E_URL_DEV` y `E2E_URL_STAGE`: en AWS deben apuntar al web de cada ambiente
   (`http://<host>:3000`) o a un túnel SSH, no a `localhost` del agente.

## 6. Aprobación de prod

El `input` usa `submitter: 'admin'`, el usuario creado por JCasC. Si el equipo tiene más
aprobadores, se deben crear usuarios/grupos y cambiar el `submitter` a un grupo (por ejemplo
`circleguard-approvers`).

## 7. Shared Library (HU-03)

La librería vive en `jenkins/vars/` y está registrada en JCasC
(`infra/bootstrap/jenkins/casc/jenkins.yaml`, `defaultVersion: dev`, `implicit: true`). El
`Jenkinsfile` usa `cgDetectChanges`, `cgGradle`, `cgUnitTests`, `cgSonar`, `cgIntegrationTests`,
`cgPackage` y `cgPublish` para el CI; `deployEnv` y `notify` siguen en el `Jenkinsfile` porque son
específicos de HU-06. Jenkins carga la librería desde `dev`, así que cualquier cambio en `jenkins/vars`
debe mergearse a esa rama antes de usarlo.

## 8. Limitaciones

- Los hosts `t3.small` de HU-01 tienen 2 GiB y no soportan los 15 contenedores; el pipeline puede
  ejecutarse contra Docker local o contra servidores más grandes.
- `QUOTA_VCPU_LIMIT=5` no permite `ci` + `nexus` + un ambiente a la vez (6 vCPU). Para la demo real
  hay que subir el límite/cuota o usar Docker local para dev/stage.
- Los 10 tests base de HU-01 dejan el build `UNSTABLE`; no bloquean el despliegue, pero deben
  corregirse en HU-04/E1.6.

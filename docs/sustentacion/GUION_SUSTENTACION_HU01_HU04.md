# Guion de sustentación · HU-01 (infraestructura) y HU-04 (pruebas)

Duración sugerida: 15–20 min de exposición + preguntas. Orden: contexto (2 min) → HU-01 (7 min) → HU-04 (7 min) → límites y cierre (2 min).

> **Regla de oro:** di primero qué se logró, luego dónde se ve, y **siempre** di también lo que NO está hecho.
> Un profesor perdona una limitación declarada; no perdona una descubierta por él.

---

## 0. Antes de la sustentación (checklist)

| Hecho | Qué |
|---|---|
| ☐ | Abre el repo en VS Code en la rama de la entrega y ten abiertas las carpetas `docs/evidencias/hu-01` y `docs/evidencias/hu-04`. |
| ☐ | Ten a mano las capturas: `docs/evidencias/hu-01/capturas/` y `docs/evidencias/hu-04/capturas/`. **Es tu plan principal**: no dependas de AWS en vivo. |
| ☐ | Abre en el navegador (sin necesidad de AWS) los HTML de `docs/evidencias/hu-04/01-informe-jacoco/*/index.html` y `02-informe-integracion/cross-service/index.html`. |
| ☐ | Decide si harás demo en vivo. Hoy **las instancias AWS están detenidas** (sección 5 explica cómo encenderlas, ~10 min y ~0,10 USD/h). |
| ☐ | Si vas a mostrar la consola de AWS: inicia sesión **antes**, en región **us-east-2 (Ohio)**. No muestres valores de secretos, ni el número de cuenta completo. |
| ☐ | Ejecuta `gradle test coverageSummary` una vez en tu máquina para tener el número a la vista y confirmar que sigue en verde. |

---

## 1. Contexto en 2 minutos (cómo abrir)

**Qué decir:**
CircleGuard es un sistema de trazabilidad de contactos con microservicios (auth, identity, promotion, form, notification, gateway, dashboard, file). En el Sprint 1 me tocaron dos historias:

- **HU-01 (E1.2):** crear con scripts Bash idempotentes y Docker Compose la infraestructura en la nube (Jenkins, SonarQube, registro de artefactos, y los ambientes dev/stage/prod aislados), con las credenciales fuera del repositorio.
- **HU-04 (E1.6):** pruebas unitarias con cobertura ≥ 60 % en los servicios núcleo y al menos 3 pruebas de integración con Testcontainers, con informes publicados por el pipeline.

**Cómo se conectan:** HU-01 construye *dónde* corre la integración continua; HU-04 es *lo que valida* esa integración continua. De hecho, el build #10 de HU-04 corrió sobre el Jenkins que creó HU-01.

**Pregunta probable:** «¿Cuál era tu aporte concreto?»
→ Responde con verbos concretos: «escribí/ejecuté…», y señala que el trabajo es del equipo (los nombres de los otros integrantes están en el repo) y qué parte fue tuya.

---

## 2. HU-01 · Infraestructura en la nube con Bash

### 2.1 Arquitectura (1 min)

**Qué decir:** AWS, región `us-east-2`. Una VPC `10.20.0.0/16` con cuatro subredes: `tools`, `dev`, `stage` y `prod`. Dos servidores grandes (`ci`: Jenkins, SonarQube, PostgreSQL; `nexus`: el registro de imágenes) y un servidor pequeño por ambiente. Secretos en SSM Parameter Store. Acceso a AWS con roles temporales y MFA, **sin claves permanentes**.

**Dónde verlo:** `docs/arquitectura/infra-ambientes.md` (diagrama) y `infra/README.md` (sección Contenido).

**Preguntas probables y respuestas**

| Pregunta | Respuesta corta |
|---|---|
| ¿Por qué AWS y no otro? | Cuenta con créditos del curso (plan gratuito), región us-east-2 y servicios necesarios (EC2, IAM, SSM) sin costo extra de gestión. |
| ¿Por qué un servidor por ambiente y no uno solo? | Aislamiento real: cada ambiente tiene su subred, grupo de seguridad, llave y secretos. Un servidor compartido no permite probar el aislamiento con tráfico. |
| ¿Por qué no usaron Terraform? | El enunciado pide Bash idempotente. Terraform garantiza idempotencia por diseño; en Bash la garantizamos con «consultar antes de crear» y la **demostramos** (ver C3). |
| ¿Cuánto cuesta? | Estimación acumulada ≈ 3 USD de 15 USD de presupuesto propio; las instancias se apagan cuando no se usan y se conservan los discos. |

### 2.2 Criterio por criterio

#### C1 · Servidores para Jenkins, SonarQube y registro de artefactos — PASS

- **Qué decir:** `ci` y `nexus` creados por script, con AMI fijada, IMDSv2 obligatorio y disco cifrado. Jenkins se configura solo con JCasC (sin asistente ni clics). SonarQube se configura por API. El registro es **CNCF Distribution** con TLS y usuario `ci`; Jenkins publica y descarga imágenes con `crane`.
- **Decisión importante que debes poder explicar:** **Nexus quedó instalado pero sin repositorio operativo, porque no se aceptó el EULA** (acuerdo de licencia). Por eso el registro real es CNCF Distribution. Es una decisión consciente, documentada en `docs/evidencias/hu-01/16-nexus-eula.md` y `docs/arquitectura/registro-artefactos.md`.
- **Dónde verlo (repo):**
  - `docs/evidencias/hu-01/14-despliegue-aws-fase4.md` (despliegue real)
  - `docs/evidencias/hu-01/aws/idempotencia/registry.txt` (publicar/descargar con `crane`: 2 PASS)
  - `docs/evidencias/hu-01/capturas/AWS-C1-ci-nexus-running.png`, `C1-salud-ci-nexus-1.png`
- **Fuera del repo:** consola de AWS (ver 5.2).

**Preguntas probables**
- *¿Por qué no aceptaron el EULA de Nexus?* → Es un acuerdo comercial que no debía aceptarse en nombre del grupo; el requisito se cumple con otro registro de artefactos y está documentado como decisión.
- *¿Cómo se configura Jenkins sin hacer clics?* → JCasC (Configuration as Code): `infra/bootstrap/jenkins/casc/jenkins.yaml`.
- *¿Por qué IMDSv2 obligatorio?* → Evita que una vulnerabilidad SSRF robe credenciales del servidor de metadatos.

#### C2 · dev, stage y prod aislados — PASS

- **Qué decir:** cada ambiente tiene su subred, grupo de seguridad, llave SSH, secretos distintos y servidor. Lo probé **con tráfico real**: dev↔stage, dev↔prod y stage↔prod están bloqueados en los dos sentidos; `ci → ambiente:22` y `ambiente → nexus:8082` están permitidos; `ambiente → ci:8080/9000` y `nexus → ambiente:22` bloqueados.
- **Dónde verlo (repo):** `docs/evidencias/hu-01/aws/aislamiento/README.md` (resultado `AISLAMIENTO VERIFICADO CON TRÁFICO`) y capturas `AWS-C2-vpc.png`, `AWS-C2-mapa-de-recursos.png`, `AWS-C2-grupos-llaves-launchtime.png`.
- **Fuera del repo:** consola AWS → VPC → grupos de seguridad.

**Preguntas probables**
- *¿Cómo demostraste el aislamiento, no solo lo configuraste?* → Script `infra/test-isolation.sh`: abre conexiones entre servidores y comprueba que fallan o pasan según lo esperado. La salida está versionada.
- *¿Y si un ambiente se compromete?* → Su grupo de seguridad no permite tráfico hacia los otros, y cada uno solo tiene su propio `.env` (permisos 0600, root).
- *¿Por qué los ambientes se encienden «por pares»?* → Límite de vCPU de la cuenta (5): se enciende solo lo necesario.

#### C3 · Scripts `infra/bootstrap-*.sh` idempotentes — PASS

- **Qué decir:** idempotente = ejecutarlo dos veces produce el mismo resultado y la segunda vez no cambia nada. El comando único es `bootstrap-all.sh`. La segunda ejecución dio **`created=0 updated=0 unchanged=137`**, y la comparación de estados (`diff S1 S2`) quedó **vacía**.
- **Prueba más fuerte:** el 2026-11-06 se **destruyó toda la infraestructura** (17 recursos, conservando secretos) y `bootstrap-all.sh` la reconstruyó **en 922 s**, con `verify-infra pass=26 fail=0`; la segunda ejecución dio `created=0 updated=0 unchanged=138`.
- **Dónde verlo (repo):**
  - `docs/evidencias/hu-01/aws/idempotencia/` (`run1.txt`, `run2.txt`, `diff-S1-S2.txt`, `report.txt`)
  - `docs/evidencias/hu-01/aws/reconstruccion/` (destrucción y reconstrucción)
  - capturas `DESTRUCCION-1-resultado.png`, `RECONSTRUCCION-1-resultado.png`
- **Cómo funciona (cuéntalo en una frase):** cada script *consulta* el estado real (por etiquetas del proyecto), compara con lo deseado y solo entonces crea o modifica; imprime `CREATED / UPDATED / UNCHANGED`.

**Preguntas probables**
- *¿Cómo sabes que es idempotente y no que «no hizo nada»?* → Por el resultado: la 1.ª ejecución muestra `CREATED`, la 2.ª `UNCHANGED` en todo, y el *snapshot* de estado no cambia. Además se probó después de destruir todo: reconstruye.
- *¿Qué pasa si falla a la mitad?* → Se puede relanzar: continúa desde lo que falta, porque cada paso consulta antes de crear.
- *¿Qué hace `--plan` vs `--apply`?* → `--plan` (por defecto) solo muestra lo que haría y valida permisos con `--dry-run`; `--apply` ejecuta. Nada cuesta dinero sin `--apply`.

#### C4 y C6 · Credenciales fuera del repositorio — PASS

- **Qué decir:** (C4) `docker-compose.dev.yml` usa `${VAR:?}` sin valores por defecto y `.env.example` vacío; las credenciales reales viven en `~/.circleguard/dev.env`. (C6) en AWS hay unos 35 parámetros **SecureString** en SSM; en los hosts, un `.env` con permisos 0600; secretos **distintos por ambiente**.
- **Prueba:** Gitleaks. En el árbol de trabajo: **0 secretos activos**. En el historial hay **51 hallazgos históricos**: son credenciales publicadas en el commit inicial del proyecto (antes de HU-01). Se tratan como **comprometidas**: no se reutilizan en ningún ambiente y no se reescribió el historial.
- **Dónde verlo (repo):** `docs/evidencias/hu-01/03-gitleaks-arbol-de-trabajo.txt`, `04-gitleaks-historial.txt`, `auditoria/`; el commit `3a43855` (`git show --stat 3a43855`); `.env.example`.
- **Fuera del repo:** consola AWS → Systems Manager → Parameter Store (muestra **nombres**, nunca valores).

**Preguntas probables**
- *Hay 51 hallazgos en el historial, ¿por qué no limpiaron el historial?* → Reescribirlo rompe a todos los colaboradores y las credenciales ya son públicas: lo correcto es **rotarlas/no reutilizarlas**, y así se hizo. Es una decisión documentada.
- *¿Qué es un falso positivo aquí?* → Valores ficticios en `src/test` (clasificados como PRUEBA) y comentarios inmutables de migraciones (RESIDUAL).
- *¿Cómo accede el sistema a los secretos?* → Los scripts leen SSM con el rol de operador y los escriben en el `.env` del host. Nada de claves permanentes.

#### C5 · Sin configuración manual no documentada — **BLOCKED** (dilo tú primero)

- **Qué decir:** el proceso está automatizado y documentado, pero el criterio exige que **otra persona** lo reconstruya solo siguiendo la documentación. Esa prueba (ensayo de reconstrucción por otro integrante) **está preparada pero pendiente** (`docs/evidencias/hu-01/ensayo-reconstruccion/`). Por eso el informe de HU-01 dice «NO cerrada».
- **Pasos que sí requieren una persona (y por qué):** escribir contraseñas y MFA solo en la página oficial de AWS; CloudShell para destruir. Está en la tabla de pasos humanos de `infra/README.md`.

**Pregunta probable:** *¿Por qué dicen que HU-01 no está cerrada?* → Porque 5 de 6 criterios están en PASS y C5 depende de un tercero. Preferimos reportarlo así que declarar un PASS sin prueba.

---

## 3. HU-04 · Pruebas unitarias y de integración

### 3.1 Resumen (30 s)
**Qué decir:** el build #10 en Jenkins terminó en **SUCCESS**: **269 pruebas, 0 fallos**; cobertura de líneas por servicio: auth **98,0 %**, identity **98,1 %**, promotion **90,9 %**, form **97,9 %**, gateway **100 %** (mínimo exigido 60 %); **5 pruebas de integración con Testcontainers**, una de ellas formulario → Kafka → promotion; reportes publicados por el pipeline.

### 3.2 Criterio por criterio

| # | Criterio | Estado | Dónde verlo |
|---|---|---|---|
| 1 | Cobertura ≥ 60 % en auth, identity, promotion, form y gateway | ✅ | `docs/evidencias/hu-04/01-informe-jacoco/coverage-summary.md`; HTML por servicio; captura `05-jacoco-promotion-service.png` |
| 2 | El pipeline falla si baja del 60 % | ✅ | `build.gradle.kts` (raíz): `jacocoTestCoverageVerification` (LINE ≥ 0,60) solo en esos 5 servicios |
| 3 | ≥ 3 pruebas de integración con Testcontainers | ✅ (5) | `tests/integration/…/FormToPromotionIntegrationTest.java` y `PromotionToNotificationIntegrationTest.java`; captura `03-informe-integracion-testcontainers-5-ok.png` |
| 4 | Una de ellas: form → Kafka → promotion | ✅ | IT-1, IT-1b, IT-2 |
| 5 | Informes publicados por el pipeline | ✅ | `Jenkinsfile` + `jenkins/vars/cgUnitTests.groovy` y `cgIntegrationTests.groovy`; `03-pipeline/consola-build10.txt` |
| 6 | Evidencia: JaCoCo, integración y captura del pipeline | ✅ | carpeta `docs/evidencias/hu-04/` y `capturas/` (7 imágenes) |

### 3.3 Cómo explicar cada pieza

**Pruebas unitarias.** Se escribieron con JUnit 5 y Mockito (y MockMvc para controladores) en cada servicio núcleo. La línea base de cobertura **antes** de mi trabajo está en `docs/evidencias/hu-04/00-linea-base-cobertura.txt`; muéstrala para evidenciar el salto.

**Pruebas de integración (las 5).** Usan Testcontainers para levantar **contenedores reales**: Kafka, PostgreSQL, Neo4j y Redis. Corren los contextos reales de Spring de `promotion` y `notification` con su propio `application.yml`, y el `HealthSurveyService` real de `form` con un `KafkaTemplate` real:
- IT-1: una encuesta con síntomas enviada por *form* convierte al usuario en SUSPECT en *promotion* (se verifica en Neo4j).
- IT-1b: una encuesta sin síntomas lo deja ACTIVE.
- IT-2: un certificado aprobado devuelve al usuario a ACTIVE.
- IT-3: un cambio de estado publicado por *promotion* se notifica por SMS y push.
- IT-4: encuesta (*form*) → SUSPECT (*promotion*) → notificación al usuario.
La verificación de la notificación se hace leyendo el *topic* `notification.audit`.

**Pipeline.** Etapas: Checkout → Build → Unit tests and coverage → (SonarQube, opcional) → Integration tests → Package → (Publish). Publica JUnit, Coverage (JaCoCo) y los HTML.

**Docker-in-Docker (dind).** Testcontainers necesita un daemon de Docker. En lugar de darle a Jenkins el socket del host (riesgoso: acceso root al servidor), se añadió un *sidecar* `dind` en la red interna de Compose, sin puerto publicado. Variables: `DOCKER_HOST=tcp://dind:2375` y `TESTCONTAINERS_HOST_OVERRIDE=dind`.

### 3.4 Defectos reales que encontraron las pruebas (esto da mucho valor)
1. **Serializador de Kafka faltante** en `application.yml` de *promotion* y *notification* (no declaraban `value-serializer` JSON): **corregido**.
2. **`HealthStatusService.updateStatus` (promotion):** la consulta Cypher no devuelve filas si el usuario no tiene contactos recientes o si el nuevo estado es ACTIVE, así que no actualiza Redis ni publica `promotion.status.changed`. **No se corrigió** (queda reportado; las pruebas lo documentan afirmando sobre Neo4j).
3. Errores heredados de HU-03 en la configuración de Jenkins: el `libraryPath` de JCasC y el nombre de la tarea de Sonar (ya corregidos en `dev` por otros compañeros; se resolvió el conflicto de fusión).

### 3.5 Preguntas probables de HU-04

| Pregunta | Respuesta |
|---|---|
| ¿Qué mide «cobertura de líneas»? | El porcentaje de líneas ejecutadas por las pruebas (JaCoCo). 641 de 705 en promotion = 90,9 %. |
| ¿Cobertura alta = pruebas buenas? | No necesariamente. Por eso se añadieron pruebas de integración con contenedores reales y aserciones de comportamiento, no solo ejecución de líneas. |
| ¿Excluyeron código para subir el número? | Solo el código **generado por Lombok** (`lombok.config` con `addLombokGeneratedAnnotation`), que JaCoCo debe ignorar por definición. No se excluyeron clases de negocio. Compara con la línea base. |
| ¿Por qué mocks y también contenedores? | Unitarias con mocks: rápidas y aíslan lógica. Integración con contenedores: prueban la interacción real (Kafka, grafos, serialización) que los mocks no detectan; de hecho hallamos el defecto del serializador. |
| ¿Por qué Testcontainers y no un Kafka compartido? | Aislamiento y reproducibilidad: cada ejecución crea y destruye sus contenedores; no hay estado ni dependencias externas. |
| ¿Qué es el gate de calidad? | `jacocoTestCoverageVerification`: falla el build si la cobertura de líneas < 60 %. |
| ¿Por qué `integrationTest` separado de `test`? | Las de integración son lentas y necesitan Docker; separarlas mantiene rápido el ciclo normal y permite correrlas en una etapa propia del pipeline. |
| ¿Por qué el dind es `privileged`? | Es requisito técnico de Docker-in-Docker. Se mitigó con red interna, sin puerto publicado y volumen propio; no se montó el socket del host. |
| ¿Qué pasa en PR/otros builds que fallaban en identity/promotion? | Eran pruebas con Testcontainers ejecutándose en `test` sin Docker en Jenkins; HU-04 las separa y provee Docker. |
| ¿Dónde están las pruebas E2E con Playwright de E1.6? | **No forman parte de HU-04** y no están implementadas: hay que decirlo. Son 3 flujos (login, cuestionario de salud, validación de acceso) sobre el cliente web, y necesitan el stack completo corriendo. |
| ¿Se probó contra GitHub real? | La validación se hizo en el Jenkins de AWS con un repositorio git temporal con el mismo contenido (la rama aún no estaba en `dev`). El flujo con GitHub (`github-token`) queda por correr tras el PR. |
| ¿SonarQube? | No se validó el *quality gate* de Sonar en esta HU (falta conectar red y token); no es criterio de HU-04. |

---

## 4. Cierre (1 min) — resumen honesto

- **HU-01:** 5/6 criterios PASS con evidencia ejecutada en AWS (idempotencia, aislamiento con tráfico, destrucción y reconstrucción en 922 s). C5 pendiente del ensayo de otro integrante.
- **HU-04:** todos los criterios de aceptación cumplidos con evidencia (269 pruebas, 90,9–100 % de cobertura, 5 integraciones). No incluye Playwright (E2E), que es otra parte de E1.6.
- **Limitaciones declaradas:** C5, Playwright, SonarQube sin validar, un defecto del producto sin corregir y la validación de pipeline con repo temporal.

---

## 5. Demostración fuera del repo (paso a paso)

> Estado actual: **`ci`, `nexus` y los ambientes están detenidos** (para no generar costo). Lo que se ve en la consola de AWS sigue disponible: instancias (detenidas), VPC, grupos de seguridad y parámetros de SSM. **El Jenkins en vivo solo se ve si encienden `ci`.**

### 5.1 Plan A (recomendado): mostrar evidencia local
Solo necesitas el repo y las capturas. No dependas de que AWS responda durante la exposición.

### 5.2 Consola de AWS (sin encender nada)
1. Entra a https://console.aws.amazon.com con tu identidad de la cuenta. Elige la región **US East (Ohio) us-east-2** (arriba a la derecha).
2. **EC2 → Instances:** verás `circleguard-ci`, `circleguard-nexus` y los tres `circleguard-env-*` (estado *Stopped*). Muestra el tipo (`m7i-flex.large`, `t3.small`) y las etiquetas `Project`/`Role`.
3. **VPC → Your VPCs → `circleguard-vpc`:** CIDR `10.20.0.0/16`. En **Subnets** las cuatro (`tools/dev/stage/prod`). En **Resource map** se ve la red completa.
4. **VPC → Security groups:** `circleguard-sg-ci`, `-nexus`, `-env-dev/stage/prod`. Abre uno y enseña las reglas de entrada (puerto 22 solo desde una IP /32 del administrador).
5. **Systems Manager → Parameter Store:** busca `/circleguard`. Muestra **nombres y tipo SecureString**, **no pulses «Show decrypted value»**.
6. **IAM → Roles:** `circleguard-hu01-reader`, `-operator`, `-teardown` (lectura, operación, destrucción); **Users:** sin claves de acceso permanentes.
7. No muestres el número de cuenta completo ni valores de secretos. Si aparece, tapa la pantalla.

### 5.3 Jenkins en vivo (solo si decides encender `ci`)
Hazlo **15–20 min antes**. Costo ≈ 0,10 USD/h; para al terminar.

1. Terminal Git Bash en la raíz del repo: `bash infra/aws-session.sh unlock` → se abre una ventana: escribe allí tu código **MFA** (nunca en un chat).
2. Encender: `bash infra/bootstrap-servers.sh --apply --approve ci`.
3. Si tu IP cambió (da *timeout* en SSH): `bash infra/bootstrap-network.sh --apply`.
4. Túnel: `bash infra/tunnel.sh jenkins 8090` (**usa 8090**: el 8080 de tu PC lo ocupa Docker Desktop con otro Jenkins). Deja la ventana abierta.
5. Abre http://localhost:8090. Usuario y contraseña de Jenkins están en SSM (`/circleguard/tools/jenkins/JENKINS_ADMIN_USER` y `…/JENKINS_ADMIN_PASSWORD`); léelos en tu terminal, no los muestres en pantalla.
6. **Dashboard → `circleguard (validacion HU-04)` → `HU04-Pruebas-unitarias-y-integracion` → #10**. Enseña: SUCCESS, *Tests* (269), *JaCoCo*, *Integration tests (cross-service)* y el *Stage View*.
7. Al terminar: `bash infra/aws-session.sh unlock` y `CG_CONFIRM=DETENER bash infra/teardown.sh --stop --apply --target aws` para apagar `ci`.

### 5.4 Demostrar la idempotencia en vivo (opcional)
- **Sin costo:** `bash infra/bootstrap-all.sh --plan` (modo por defecto) recorre todos los pasos en AWS **sin cambiar nada** y muestra el costo estimado; necesita la sesión de operador (`unlock`). Cada paso imprime `UNCHANGED` si ya está convergido.
- **Local:** cada herramienta se valida por separado con `bash infra/bootstrap-<herramienta>.sh --target local` (Docker Desktop); `bootstrap-all.sh` solo aplica a AWS.
- La demostración real, con dos ejecuciones y `diff` vacío, ya está en `aws/idempotencia/` y `aws/reconstruccion/`; muéstrala desde el repo.

### 5.5 Demostrar HU-04 en vivo en tu PC (gratis, requiere Docker Desktop)
```
gradle test coverageSummary                      # unitarias + tabla de cobertura
gradle :tests:integration:integrationTest        # 5 pruebas con contenedores reales (tarda unos minutos)
```
Informe de cobertura por servicio: `services/<servicio>/build/reports/jacoco/test/html/index.html`.

---

## 6. Preguntas «difíciles» transversales

1. **¿Qué harías distinto?** → Terraform/CloudFormation para infraestructura declarativa; Playwright desde el inicio; Sonar conectado desde HU-03; ensayo de reconstrucción por un tercero antes de cerrar.
2. **¿Qué riesgos de seguridad quedan?** → dind privilegiado (mitigado por red interna); 51 credenciales históricas en el historial de git (comprometidas, no reutilizadas); SSH restringido a una IP /32 que cambia y hay que actualizar.
3. **¿Cómo escala esto?** → Ambientes por pares por límite de vCPU; el pipeline puede paralelizar etapas por servicio; la base de coste hoy es mínima.
4. **¿Cómo sabes que tus pruebas detectan errores reales?** → Las pruebas de integración encontraron el serializador JSON de Kafka faltante y el defecto de `updateStatus`.
5. **¿Qué parte del trabajo fue manual?** → Solo los pasos humanos documentados: autenticación en la página de AWS con MFA y la destrucción en CloudShell.
6. **¿Por qué el costo se mantiene bajo?** → Instancias detenidas cuando no se usan; sin NAT Gateway; tipos del plan gratuito.

---

## 7. Notas de coherencia para que no te pillen

- `docs/evidencias/hu-01/capturas/README.md` aún dice «capturas pendientes de tomar», pero la carpeta ya tiene PNG: si lo abres, aclara que el README quedó desactualizado o actualízalo antes.
- En HU-01 el número de parámetros SSM aparece como 35 y como 36 en documentos distintos: di «unos 35».
- Cobertura agregada en Jenkins = **93,36 %** (todos los servicios juntos); por servicio: 90,9–100 %. Ambos números son correctos; explícalo si preguntan.
- Las fechas de los builds en Jenkins están en hora local; los logs, en UTC.

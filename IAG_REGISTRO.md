# Anexo · Bitácora de uso de IA generativa (IAG)

Este anexo resume cómo el equipo usó IA generativa en CircleGuard, dónde están los **prompts** empleados y
qué aprendimos. El detalle turno por turno (prompt literal, respuesta resumida, decisiones y archivos) está
en [`docs/iag/`](docs/iag/README.md); las decisiones numeradas, en [`docs/iag/decisiones.md`](docs/iag/decisiones.md).

## 1. Nivel de uso

El proyecto trabaja en el **Nivel 3 · colaboración con IAG**: la IA propone y ejecuta tareas acotadas, y
**el equipo revisa, entiende y puede explicar cada resultado**. Nada entra al repositorio sin que una persona
lo haya leído, y los commits, los push y los PR los hace siempre una persona.

## 2. Reglas que aplicamos

| Regla | Cómo se cumple |
|---|---|
| Sin secretos en prompts ni en el repositorio | Contraseñas y códigos MFA se escriben solo en la página de AWS o en la terminal de la persona; la IA enmascara la cuenta y no imprime valores de SSM |
| La IA no publica | Sin commit ni push por la IA; los PR los abre una persona |
| Acciones con costo o riesgo requieren autorización expresa | Encender instancias, cambiar reglas de red o detener servicios solo con permiso explícito; las acciones de destrucción las hace una persona desde CloudShell |
| La evidencia es real | No se simulan salidas ni capturas; lo que no se pudo ejecutar se declara como pendiente |
| El registro no se reescribe | Si una decisión cambia, se añade una entrada nueva |

## 3. Índice de sesiones

| Fecha | Historia | Herramienta · modelo | Sesión (prompts y respuestas) |
|---|---|---|---|
| 2026-11-02 | HU-02 · Imágenes Docker inmutables | OpenCode · DeepSeek V4.1 Flash 1017 | [`2026-11-02-hu-02.md`](docs/iag/sesiones/2026-11-02-hu-02.md) |
| 2026-11-05 | HU-06 · Entrega continua y promoción | OpenCode · DeepSeek V4.1 Flash 1017 | [`2026-11-05-hu-06.md`](docs/iag/sesiones/2026-11-05-hu-06.md) |
| 2026-11-08 | HU-06 · Ejecución real en AWS | OpenCode · DeepSeek V4.1 Flash 1017 | [`2026-11-08-hu-06-ejecucion.md`](docs/iag/sesiones/2026-11-08-hu-06-ejecucion.md) |
| 2026-11-08 | HU-07 · Rollback, notificaciones y release notes | OpenCode · DeepSeek V4.1 Flash 1017 | [`2026-11-08-hu-07.md`](docs/iag/sesiones/2026-11-08-hu-07.md) |
| 2026-11-07/08 | HU-04 · Pruebas unitarias y de integración | Claude Code · Claude Sonnet 5.5 | [`2026-11-08-hu-04.md`](docs/iag/sesiones/2026-11-08-hu-04.md) |
| 2026-11-08 | HU-08 · Documentación y bitácora | Claude Code · Claude Sonnet 5.5 | [`2026-11-08-hu-08.md`](docs/iag/sesiones/2026-11-08-hu-08.md) |

**Decisiones asistidas:** D-01 a D-25 en [`docs/iag/decisiones.md`](docs/iag/decisiones.md).

### Cobertura de la bitácora (lagunas declaradas)

No hay sesión registrada para **HU-01** (infraestructura), **HU-03** (pipeline multibranch) ni **HU-09**
(ramas y commits). Si el equipo usó IA en ellas, falta añadir su sesión con
[`docs/iag/plantilla-sesion.md`](docs/iag/plantilla-sesion.md); este anexo no inventa prompts que no se
conservaron. Para HU-04, el primer prompt se conserva solo como síntesis (la sesión se resumió por límite de
contexto), y así se indica en su archivo.

## 4. Cómo verificamos lo que la IA produjo

| Tipo de resultado | Verificación |
|---|---|
| Código y pruebas | Ejecución real: `gradle test`, cobertura JaCoCo y el pipeline de Jenkins (build #10 de HU-04) |
| Scripts de infraestructura | `--plan` primero, ShellCheck, y ejecución en AWS con salida versionada y enmascarada (HU-01) |
| Afirmaciones sobre el repositorio | Lectura del código fuente o del log; por ejemplo, los tópicos de Kafka de los diagramas se tomaron de `HealthSurveyService` y los `@KafkaListener` |
| Revisión de PR de otra historia | Contraste con los commits, los logs y los archivos reales de la rama |
| Secretos | `infra/scan-secrets.sh` (Gitleaks) y `infra/check-evidence.sh` antes de versionar evidencias |

## 5. Reflexión crítica

### Qué aportó la IA
- **Velocidad en trabajo repetitivo y de volumen:** pruebas unitarias para cinco servicios (cobertura de 90,9 % a
  100 %), scripts de despliegue y documentación.
- **Descubrir defectos al escribir pruebas:** al probar de extremo a extremo apareció que promotion y notification
  no declaraban el serializador JSON de Kafka, y que `HealthStatusService.updateStatus` no devuelve filas sin
  contactos recientes o con estado `ACTIVE`.
- **Revisión cruzada:** comparar un PR contra los logs reales encontró que el texto decía «10 tests» cuando
  fallaban 14, y «registry Nexus» cuando el registro es CNCF Distribution.

### Dónde se equivocó la IA (y cómo se detectó)
| Error | Cómo se detectó |
|---|---|
| Sugirió un comando que no existe (`bootstrap-all.sh --plan --target local`) para una demostración | Al leer el script: solo aplica a AWS. Se corrigió antes de entregarlo |
| Mantuvo un vigilante que dejó de informar al caducar el rol de AWS (1 h) | La persona preguntó por el estado del build; se reabrió la sesión |
| Dio por hecho que `ci` seguía encendida cuando la parada automática de 4 h ya la había apagado | Falló el SSH; se consultó el estado real de la instancia |
| Capturas tomadas en el Jenkins equivocado (el puerto 8080 de la PC lo ocupaba Docker Desktop) | Los números de build no coincidían; se usó el túnel en el puerto 8090 |
| Afirmó que no había Playwright en el repo, cierto en su rama pero obsoleto tras integrar HU-06 | Al releer el árbol tras la fusión |
| Historias anteriores: la verificación de imágenes y el tag/release de HU-07 necesitaron correcciones posteriores | Registradas en las sesiones de [HU-02](docs/iag/sesiones/2026-11-02-hu-02.md) y [HU-07](docs/iag/sesiones/2026-11-08-hu-07.md) |

### Riesgos que vimos
- **Sobreconfianza:** una salida plausible no es una salida verificada; por eso exigimos ejecución real y logs.
- **Evidencia fabricada:** la tentación de «completar» capturas o resultados. La regla es declarar lo pendiente
  (por ejemplo, SonarQube sin conectar o Playwright con solo 2 pruebas de humo).
- **Fuga de secretos:** el historial de git ya contenía 51 credenciales del commit inicial; la IA no debe ver ni
  repetir secretos, y las evidencias se escanean antes de versionarlas.
- **Acciones con costo:** una instancia olvidada cuesta dinero; todas se apagan solas a las 4 h y se detienen al terminar.
- **Dependencia entre historias:** HU-04 y HU-06 compartían el mismo Docker-in-Docker; sin coordinación, una
  saturó a la otra. La decisión humana de esperar resolvió el conflicto.

### Qué aprendimos y qué haríamos distinto
1. Registrar el prompt **literal** desde el primer turno de cada historia (en HU-04 se perdió el primero).
2. Verificar siempre el **estado real** (instancia, rama, puerto) antes de actuar sobre una suposición.
3. Mantener la **separación entre IA y publicación**: que la persona haga commit, push y PR obliga a leer el diff.
4. Dejar las lagunas visibles. Una bitácora honesta con huecos vale más que una completa pero inventada.
5. Documentar a medida que se avanza: la mayor parte de las correcciones salieron de comparar la documentación con el código.

## 6. Dónde está cada cosa

| Qué | Dónde |
|---|---|
| Prompts y respuestas por historia | [`docs/iag/sesiones/`](docs/iag/sesiones/) |
| Decisiones con alternativas y consecuencias | [`docs/iag/decisiones.md`](docs/iag/decisiones.md) |
| Plantilla para nuevas sesiones | [`docs/iag/plantilla-sesion.md`](docs/iag/plantilla-sesion.md) |
| Reglas del registro | [`docs/iag/README.md`](docs/iag/README.md) |

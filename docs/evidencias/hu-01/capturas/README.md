# Capturas de pantalla de HU-01: instrucciones (pendientes de tomar)

La regla de la p. 6 del enunciado dice que las evidencias sin captura no se califican, y el
informe PDF (p. 9) pide capturas. **Esta carpeta no contiene capturas todavía**: las toma una
persona frente a su terminal o su navegador. No se generan ni se simulan.

La evidencia verificable son las salidas de texto enmascaradas versionadas en
[`../aws/`](../aws/README.md) y [`../auditoria/`](../auditoria/). Las capturas las acompañan en el
informe PDF.

Guárdelas aquí con el nombre indicado (PNG).

**Antes de guardar, compruebe que no aparecen:**
- contraseñas, el contenido de un `.env` ni valores de SSM;
- IP públicas completas;
- el número de cuenta.

## Capturas que se pueden tomar ya (sin AWS)

Las salidas de las pruebas del 2026-11-03 y del 2026-11-03/04 ya están en el repositorio. Basta
con mostrarlas en la terminal desde la raíz del repositorio.

| Archivo | Criterio | Comando | Qué debe verse |
|---|---|---|---|
| `C3-idempotencia-report.png` | C1, C3 | `cat docs/evidencias/hu-01/aws/idempotencia/report.txt` | Las líneas PASS, `RESULTADO: IDEMPOTENTE` e `instancias detenidas al terminar` |
| `C3-segunda-ejecucion.png` | C3 | `grep SUMMARY docs/evidencias/hu-01/aws/idempotencia/run2.txt` | `bootstrap-all created=0 updated=0` y los resúmenes de cada paso |
| `C1-registro-jenkins.png` | C1 | `grep -E 'PASS\|FAIL\|SUMMARY' docs/evidencias/hu-01/aws/idempotencia/registry.txt` | `PASS registry: el usuario ci publica y descarga…` y `PASS registry: Jenkins (contenedor cg-jenkins) se autentica, publica y descarga con crane` |
| `C1-salud.png` | C1 | `grep -E 'PENDING\|FAIL\|SUMMARY' docs/evidencias/hu-01/aws/idempotencia/health-after-restart.txt` | `verify-infra pass=25 fail=0 pendiente=1`. El único PENDING es Nexus sin EULA: el texto es el del commit `3afca6f`, y el código actual lo informa como PASS ([nota](../aws/idempotencia/README.md)) |
| `C2-aislamiento-report.png` | C2, C3 | `cat docs/evidencias/hu-01/aws/aislamiento/fases-1-3/report.txt docs/evidencias/hu-01/aws/aislamiento/fases-4-5/report.txt` | Las cinco fases en PASS, la idempotencia de `bootstrap-env.sh`, `RESULTADO: AISLAMIENTO VERIFICADO CON TRÁFICO` e `instancias detenidas al terminar` |
| `C2-flujos-bloqueados.png` | C2 | `grep -hE 'aislamiento:\|permitido:' docs/evidencias/hu-01/aws/aislamiento/fases-*/fase*.txt` | Los 6 flujos entre ambientes y los de `ci`/`nexus` en PASS |
| `E4-gitleaks-arbol.png` | C4, C6 y evidencia 4 | `bash infra/scan-secrets.sh --worktree` | `== worktree: 11 hallazgos PRUEBA=9 RESIDUAL=2` y `PASS el árbol de trabajo no contiene secretos activos` (los valores salen redactados) |
| `E4-gitleaks-historial.png` | C6 | `bash infra/scan-secrets.sh --history` | El resumen con los 51 hallazgos HISTÓRICO, que no se reescriben |

## Capturas que requieren AWS u otra persona

| Archivo | Criterio | Requiere | Cómo obtenerla | Qué debe verse |
|---|---|---|---|---|
| `C1-jenkins-ui.png` | C1 | Instancias encendidas (sesión autorizada) | Durante una sesión con `ci` encendida, en otra terminal: `bash infra/tunnel.sh jenkins`; abrir `http://localhost:8080` | La pantalla de inicio de sesión o el panel, sin escribir la contraseña en la imagen |
| `C1-sonarqube-ui.png` | C1 | Igual | `bash infra/tunnel.sh sonarqube`; abrir `http://localhost:9000` | La pantalla de inicio de sesión de SonarQube |
| `C5-reconstruccion.png` | C5 | El otro integrante | La toma B durante el ensayo de nivel 1 ([`../ensayo-reconstruccion/`](../ensayo-reconstruccion/README.md)) | `check-prerequisites.sh` con `fail=0`, las llaves restauradas por `bootstrap-secrets.sh` y el `report.txt` de su prueba |

Las capturas de Jenkins y SonarQube se toman en la sesión de la demostración, con `ci` encendida.
La prueba de aislamiento no sirve para eso: detiene los servidores entre fases.

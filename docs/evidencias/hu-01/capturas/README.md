# Capturas de pantalla de HU-01: instrucciones (pendientes de tomar)

La regla de la p. 6 del enunciado dice que las evidencias sin captura no se califican, y el
informe PDF (p. 9) pide capturas. **Esta carpeta no contiene capturas todavía**: todas requieren
una persona frente a una terminal o un navegador y, salvo C4/C6, una sesión de AWS autorizada.

Guárdelas aquí con el nombre indicado (PNG).

**Antes de guardar, compruebe que no aparecen:**
- contraseñas, el contenido de un `.env` ni valores de SSM;
- IP públicas completas;
- el número de cuenta.

| Archivo | Criterio | Requiere AWS | Cómo obtenerla | Qué debe verse |
|---|---|---|---|---|
| `E4-gitleaks-arbol.png` | C4, C6 y evidencia 4 | No | Desde la raíz del repositorio: `bash infra/scan-secrets.sh --worktree` | `== worktree: 11 hallazgos PRUEBA=9 RESIDUAL=2` y `PASS el árbol de trabajo no contiene secretos activos` (los valores salen redactados) |
| `E4-gitleaks-historial.png` | C6 | No | `bash infra/scan-secrets.sh --history` | El resumen con los 51 hallazgos HISTÓRICO, que no se reescriben |
| `C3-idempotencia-report.png` | C3 | Sí (autorización) | Tras `bash infra/test-idempotency.sh --apply --approve ci,nexus`: `cat ~/.circleguard/idempotency/<marca>/masked/report.txt` | Las líneas PASS y `RESULTADO: IDEMPOTENTE` |
| `C1-registro-jenkins.png` | C1 | Sí (misma sesión) | `cat ~/.circleguard/idempotency/<marca>/masked/registry.txt` | `PASS registry: el usuario ci publica y descarga…` y `PASS registry: Jenkins (contenedor cg-jenkins) se autentica, publica y descarga con crane` |
| `C1-jenkins-ui.png` | C1 | Sí (misma sesión, antes de la parada) | En otra terminal, `bash infra/tunnel.sh jenkins`; abrir `http://localhost:8080` | La pantalla de inicio de sesión o el panel, sin escribir la contraseña en la imagen |
| `C1-sonarqube-ui.png` | C1 | Sí (misma sesión) | `bash infra/tunnel.sh sonarqube`; abrir `http://localhost:9000` | La pantalla de inicio de sesión de SonarQube |
| `C2-aislamiento-report.png` | C2 | Sí (autorización) | Tras `bash infra/test-isolation.sh --apply`: `cat ~/.circleguard/isolation/<marca>/masked/report.txt` | Las cinco fases en PASS y las líneas `aislamiento: env-… bloqueado` |
| `C5-reconstruccion.png` | C5 | Sí (autorización) | La toma el otro integrante durante el ensayo de nivel 1 ([`../ensayo-reconstruccion/`](../ensayo-reconstruccion/README.md)) | La salida de `check-prerequisites.sh` con `fail=0`, las llaves restauradas por `bootstrap-secrets.sh` y el `report.txt` de la prueba |

Las salidas de texto enmascaradas de esas mismas ejecuciones (`masked/`) se copian a
`docs/evidencias/hu-01/aws/` (carpeta que se creará con la primera ejecución autorizada) y son la
evidencia verificable; las capturas la acompañan en el informe PDF.

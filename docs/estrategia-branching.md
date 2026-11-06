# Estrategia de branching y Conventional Commits

HU-09. CircleGuard.

## 1. Estrategia elegida: GitHub Flow

`main` es la única rama permanente. Siempre es desplegable. Todo cambio entra por Pull Request desde una rama corta.

### Flujo

1. Crear rama desde `main` actualizada.
2. Commits pequeños en Conventional Commits.
3. Push de la rama. Jenkins multibranch (HU-03) ejecuta el pipeline.
4. Abrir Pull Request hacia `main`.
5. Revisión de al menos una persona.
6. Checks requeridos en verde.
7. Merge. Borrar la rama.

### Nombres de rama

| Prefijo | Uso | Ejemplo |
|:---|:---|:---|
| `feature/` | Funcionalidad nueva | `feature/hu-05-e2e-playwright` |
| `fix/` | Corrección de errores | `fix/gateway-qr-expiracion` |
| `docs/` | Documentación | `docs/estrategia-branching` |
| `chore/` | Mantenimiento | `chore/actualizar-gradle` |
| `HU-NN_` | Rama por historia de usuario (convención actual del equipo) | `HU01_Infraestructura_nube_bash` |

## 2. Justificación

| Criterio | GitHub Flow | Trunk-based puro | Git Flow |
|:---|:---|:---|:---|
| Complejidad | Baja | Baja | Alta |
| Revisión por PR | Sí, obligatoria | Opcional | Sí |
| Ramas de larga vida | Ninguna | Ninguna | `develop`, `release` |
| Encaja con equipo de 3 personas | Sí | Requiere feature flags | Excesivo |
| Encaja con Jenkins multibranch | Sí, una rama = un build | Sí | Sí, pero más ramas |
| Encaja con promoción dev/stage/prod | Sí, por imagen y tag | Sí | Duplica con ramas |

Razones:

- Equipo pequeño y proyecto académico. Git Flow añade ramas sin beneficio.
- La promoción entre ambientes (HU-06) se hace con imágenes versionadas, no con ramas.
- Trunk-based exige feature flags y cultura de integración continua madura. El equipo aún no los tiene.
- Cada rama dispara un build en Jenkins. El PR muestra el resultado antes del merge.
- El historial lineal facilita auditoría y reversión.

## 3. Protección de `main`

| Regla | Valor |
|:---|:---|
| Pull Request obligatorio | Sí |
| Aprobaciones mínimas | 1 |
| Descartar aprobaciones obsoletas al nuevo push | Sí |
| Checks requeridos | `commit-lint` y el check de Jenkins |
| Rama actualizada antes de merge | Sí |
| Conversaciones resueltas | Sí |
| Historial lineal | Sí (squash o rebase merge) |
| Aplica a administradores | Sí |
| Force push | Bloqueado |
| Borrar `main` | Bloqueado |

### Aplicar la regla

Opción A. Script con GitHub CLI:

```bash
gh auth login
CHECKS="commit-lint" scripts/setup-branch-protection.sh
```

Cuando Jenkins reporte status a GitHub (HU-03), agregar su contexto:

```bash
CHECKS="commit-lint,continuous-integration/jenkins/pr-merge" scripts/setup-branch-protection.sh
```

El nombre exacto del contexto de Jenkins se confirma en un PR real, en la sección de checks.

Opción B. Interfaz web: Settings → Branches → Add branch ruleset (o classic rule) → `main`.

Nota: en repositorios privados de una organización, la protección de ramas requiere plan de pago. Si la opción no aparece, se documenta la limitación y se usa un repositorio personal o público para la evidencia.

## 4. Conventional Commits

Formato:

```
<tipo>(<alcance opcional>): <descripción en imperativo>

<cuerpo opcional>

<pie opcional>
```

### Tipos permitidos

| Tipo | Uso |
|:---|:---|
| `feat` | Funcionalidad nueva |
| `fix` | Corrección de error |
| `docs` | Solo documentación |
| `style` | Formato sin cambio de lógica |
| `refactor` | Reestructura sin cambio funcional |
| `perf` | Mejora de rendimiento |
| `test` | Pruebas |
| `build` | Gradle, dependencias, Docker |
| `ci` | Jenkins, GitHub Actions |
| `chore` | Mantenimiento |
| `revert` | Reversión |

Cambio incompatible: agregar `!` tras el tipo o alcance, por ejemplo `feat(api)!: eliminar endpoint v1`.

### Alcances sugeridos

`auth`, `identity`, `promotion`, `notification`, `form`, `file`, `gateway`, `dashboard`, `mobile`, `infra`, `jenkins`, `e2e`, `docs`.

### Ejemplos

```
feat(jenkins): agregar shared library con etapas reutilizables
fix(gateway): corregir expiración del token QR
ci(e2e): publicar informe de Playwright en el pipeline
docs: documentar estrategia de branching
```

### Validación

- Local: hook `commit-msg`.

```bash
git config core.hooksPath .githooks
chmod +x .githooks/commit-msg scripts/check-conventional-commits.sh
```

- Remoto: workflow `commit-lint` en cada PR hacia `main`. Es un check requerido.
- Manual:

```bash
scripts/check-conventional-commits.sh origin/main..HEAD
```

## 5. Evidencias

| Evidencia | Ubicación |
|:---|:---|
| Captura de la regla de protección | `docs/evidencias/hu-09/01-regla-proteccion-main.png` |
| Captura de PR bloqueado sin revisión | `docs/evidencias/hu-09/02-pr-bloqueado.png` |
| Captura del check `commit-lint` | `docs/evidencias/hu-09/03-check-commit-lint.png` |
| Historial de commits | `docs/evidencias/hu-09/04-historial-commits.txt` |
| Este documento | `docs/estrategia-branching.md` |

Generar el historial:

```bash
git log --format='%h %an %s' origin/main > docs/evidencias/hu-09/04-historial-commits.txt
```

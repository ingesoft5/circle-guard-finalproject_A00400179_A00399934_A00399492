# Estrategia de branching y Conventional Commits

HU-09. CircleGuard.

## 1. Estrategia elegida: GitHub Flow con rama de integración `dev`

Dos ramas permanentes:

- `dev`: integración. Recibe todas las ramas de historia de usuario. Despliega al ambiente dev y stage.
- `main`: producción. Solo recibe PR desde `dev`. Siempre es desplegable y cada merge genera un release con tag semántico.

Todo cambio entra por Pull Request desde una rama corta. Nadie hace push directo a `main` ni a `dev`.

### Flujo

1. Crear la rama de la historia desde `dev` actualizada.
2. Commits pequeños en Conventional Commits.
3. Push de la rama. Jenkins multibranch (HU-03) ejecuta el pipeline.
4. Abrir Pull Request hacia `dev`.
5. Revisión de al menos una persona distinta al autor.
6. Checks requeridos en verde (`commit-lint` y Jenkins).
7. Merge a `dev` (squash). Borrar la rama.
8. Cuando `dev` está estable y pasó las pruebas E2E, abrir un PR de `dev` hacia `main`.
9. Aprobación manual de producción en Jenkins (HU-06) y merge con merge commit. Se crea el tag de release.

### Nombres de rama

| Prefijo | Uso | Ejemplo |
|:---|:---|:---|
| `HU-NN_` | Rama por historia de usuario (convención del equipo) | `HU-09_Branching-conventional-commits` |
| `fix/` | Corrección urgente | `fix/gateway-qr-expiracion` |
| `docs/` | Documentación | `docs/estrategia-branching` |
| `chore/` | Mantenimiento | `chore/actualizar-gradle` |

## 2. Justificación

| Criterio | GitHub Flow | Trunk-based puro | Git Flow |
|:---|:---|:---|:---|
| Criterio | GitHub Flow + `dev` | Trunk-based puro | Git Flow |
|:---|:---|:---|:---|
| Complejidad | Baja | Baja | Alta |
| Revisión por PR | Sí, obligatoria | Opcional | Sí |
| Ramas de larga vida | Una (`dev`) | Ninguna | `develop`, `release`, `hotfix` |
| Encaja con equipo de 3 personas | Sí | Requiere feature flags | Excesivo |
| Encaja con Jenkins multibranch | Sí, una rama = un build | Sí | Sí, pero más ramas |
| Encaja con promoción dev/stage/prod | Sí: `dev` despliega dev y stage, `main` pide aprobación a prod | Sí | Duplica con ramas |

Razones:

- Equipo pequeño y proyecto académico. Git Flow añade ramas sin beneficio.
- La promoción entre ambientes (HU-06) se hace con imágenes versionadas. `dev` integra y valida; `main` es lo que llega a producción.
- Trunk-based exige feature flags y cultura de integración continua madura. El equipo aún no los tiene.
- Cada rama dispara un build en Jenkins. El PR muestra el resultado antes del merge.
- El historial lineal facilita auditoría y reversión.

## 3. Protección de `main` y `dev`

Las dos ramas llevan las mismas reglas.

| Regla | Valor |
|:---|:---|
| Pull Request obligatorio | Sí |
| Aprobaciones mínimas | 1 |
| Descartar aprobaciones obsoletas al nuevo push | Sí |
| Checks requeridos | `commit-lint` y el check de Jenkins |
| Rama actualizada antes de merge | Sí |
| Conversaciones resueltas | Sí |
| Aplica a administradores | Sí |
| Force push | Bloqueado |
| Borrar la rama | Bloqueado |

Tipo de merge: squash hacia `dev`; merge commit de `dev` hacia `main`, para que `dev` no diverja de `main`.

### Aplicar la regla

Opción A. Script con GitHub CLI:

```bash
gh auth login
BRANCH=main CHECKS="commit-lint" scripts/setup-branch-protection.sh
BRANCH=dev CHECKS="commit-lint" scripts/setup-branch-protection.sh
```

Cuando Jenkins reporte status a GitHub (HU-03), agregar su contexto:

```bash
BRANCH=main CHECKS="commit-lint,continuous-integration/jenkins/pr-merge" scripts/setup-branch-protection.sh
```

El nombre exacto del contexto de Jenkins se confirma en un PR real, en la sección de checks.

Opción B. Interfaz web: Settings → Branches → Add branch ruleset (o classic rule) → `main` y `dev`.

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

- Remoto: workflow `.github/workflows/commit-lint.yml` en cada PR hacia `main` y `dev`. Es un check requerido.
- Manual:

```bash
scripts/check-conventional-commits.sh origin/dev..HEAD
```

## 5. Evidencias

| Evidencia | Ubicación |
|:---|:---|
| Captura de la regla de protección de `main` y `dev` | `docs/evidencias/hu-09/01-regla-proteccion.png` |
| Captura de PR bloqueado sin revisión | `docs/evidencias/hu-09/02-pr-bloqueado.png` |
| Captura del check `commit-lint` | `docs/evidencias/hu-09/03-check-commit-lint.png` |
| Historial de commits | `docs/evidencias/hu-09/04-historial-commits.txt` |
| Este documento | `docs/estrategia-branching.md` |

Generar el historial:

```bash
git log --format='%h %an %s' origin/dev > docs/evidencias/hu-09/04-historial-commits.txt
```

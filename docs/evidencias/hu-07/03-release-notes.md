# 03 · Release notes y GitHub Release

Fecha: 2026-11-08
Versión: `0.2.0`
Tag: `v0.2.0` → commit `59cec5c`
Versión anterior: `v0.1.0` → commit `dd825e6`

## Archivos generados

- `docs/release-notes/v0.2.0.md` — notas completas de la versión.
- `CHANGELOG.md` — sección `[v0.2.0] - 2026-11-08`.
- `docs/release-notes/v0.1.0.md` — notas de la versión anterior.

## Generación

```bash
./deploy/release-notes.sh 0.2.0
```

Salida del build #18:

```text
Release notes: /var/jenkins_home/workspace/circleguard-hu06-v2_HU-06-run/docs/release-notes/v0.2.0.md
CHANGELOG actualizado: /var/jenkins_home/workspace/circleguard-hu06-v2_HU-06-run/CHANGELOG.md
```

## Contenido de v0.2.0

Features:

- Completar release notes, GitHub Release y documentación de HU-07.
- Semilla de change management y release notes.

Fixes:

- Publicar el tag en GitHub desde Jenkins.
- Publicar artifacts con netrc y evitar falso positivo de gitleaks.
- Consultar la versión actual sin abortar.
- Reportar la línea que falla.
- Aceptar imágenes locales en despliegues locales.

Otros:

- Integración de HU-06 y HU-04 en `dev`.
- Evidencias de build y rollback.

## GitHub Release

URL: <https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492/releases/tag/v0.2.0>

El release se creó inicialmente con un target incorrecto porque `tag-release.sh` no reconocía
`PUSH_TAG=true`. Se corrigió el script (`deploy/tag-release.sh`, `deploy/github-release.sh`) y se
recreó el tag/release apuntando a `59cec5c`.

## Relación con el rollback

La release `v0.2.0` queda publicada y taggeada, pero los ambientes se devolvieron a `0.1.0` como
parte de la verificación de HU-07:

- dev: `0.1.0` (rollback real, build #19).
- prod: `0.1.0` (rollback real, build #21).
- Tag/release: `v0.2.0` en `59cec5c`.

Ver `01-rollback.txt` y `04-tag.txt`.

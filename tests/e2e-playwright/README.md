# Pruebas E2E · Playwright

Suite del gate de promoción de HU-06 y de HU-05.

| Archivo | Flujo |
| --- | --- |
| `smoke.spec.ts` | El cliente responde y `/healthz` da `200`. |
| `login.spec.ts` | Flujo 1: inicio de sesión válido e inválido. |
| `questionnaire.spec.ts` | Flujo 2: cuestionario de salud. |
| `access.spec.ts` | Flujo 3: QR de acceso y escáner de la puerta. |

Los flujos interceptan las llamadas a `/api/v1/**` con `page.route`. Así son
deterministas y no dependen de usuarios LDAP ni de datos sembrados. Corren contra
cualquier URL de ambiente (`E2E_BASE_URL`).

## Ejecutar

```bash
cd tests/e2e-playwright
npm install
npx playwright install chromium
E2E_BASE_URL=http://localhost:3000 npm test
```

O desde la raíz:

```bash
E2E_BASE_URL=http://localhost:3000 ./deploy/e2e.sh dev
```

## En Jenkins

El agente debe tener Node 22 y los navegadores de Playwright, o ejecutar el paso dentro de la
imagen `mcr.microsoft.com/playwright`. Si el agente ya tiene los navegadores instalados, use
`PLAYWRIGHT_INSTALL_BROWSERS=0`.

## Reportes

- `results.xml` (JUnit, para Jenkins).
- `playwright-report/` (HTML).
- `test-results/` (capturas de cada prueba, trazas y videos de fallos).

No se versionan; el pipeline los archiva.

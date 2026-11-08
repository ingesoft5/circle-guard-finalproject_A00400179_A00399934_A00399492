# Pruebas E2E · Playwright

Suite mínima de humo para el gate de promoción de HU-06. Verifica que el cliente web
responde y que el healthcheck del proxy (`/healthz`) está en `200`.

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
- `test-results/` (trazas y capturas de fallos).

No se versionan; el pipeline los archiva.

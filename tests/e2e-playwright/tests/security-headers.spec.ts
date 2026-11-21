import { expect, test } from '@playwright/test';
import { mockQrToken, seedSession } from './support';

/**
 * HU-15: the web client's nginx sends security headers (mobile/nginx.conf) and a Content-Security-Policy.
 * - The "no CSP violation" check always runs: the application must work under the policy and the policy must not be relaxed to make it pass.
 * - The "headers are present" check runs only when E2E_EXPECT_SECURITY_HEADERS=1, because the local static server of the
 *   RUN_E2E_LOCAL stage is not nginx and does not send them. Set it when E2E_BASE_URL points at the nginx of an environment.
 */
const ROUTES = ['/', '/login', '/questionnaire', '/scan', '/report'];

test.describe('Cabeceras de seguridad del cliente web', () => {
  test('ninguna pantalla viola la Content-Security-Policy', async ({ page }) => {
    const violations: string[] = [];
    await page.addInitScript(() => {
      document.addEventListener('securitypolicyviolation', (event) => {
        (window as unknown as { __csp: string[] }).__csp = [
          ...((window as unknown as { __csp?: string[] }).__csp ?? []),
          `${event.violatedDirective} blocked ${event.blockedURI}`,
        ];
      });
    });
    page.on('console', (message) => {
      if (/Content Security Policy/i.test(message.text())) {
        violations.push(message.text());
      }
    });
    await seedSession(page);
    await mockQrToken(page);
    await page.route('**/api/v1/questionnaires/active', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ id: 'q', title: 'Daily', questions: [] }) }),
    );
    for (const route of ROUTES) {
      await page.goto(route);
      await page.waitForLoadState('load');
      await page.waitForTimeout(1500); // let the client render and run its scripts; some screens poll APIs that are not mocked
      const fromEvents = await page.evaluate(() => (window as unknown as { __csp?: string[] }).__csp ?? []);
      violations.push(...fromEvents.map((v) => `${route}: ${v}`));
    }
    expect(violations).toEqual([]);
  });

  test('el servidor envía las cabeceras de seguridad', async ({ request }) => {
    test.skip(process.env.E2E_EXPECT_SECURITY_HEADERS !== '1', 'solo contra el nginx de un ambiente (E2E_EXPECT_SECURITY_HEADERS=1)');
    const response = await request.get('/');
    const headers = response.headers();
    expect(headers['content-security-policy']).toContain("default-src 'self'");
    expect(headers['content-security-policy']).toContain("frame-ancestors 'none'");
    expect(headers['content-security-policy']).not.toContain("script-src 'self' 'unsafe-inline'");
    expect(headers['x-frame-options']).toBe('DENY');
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['permissions-policy']).toContain('camera=(self)');
    expect(headers['cross-origin-opener-policy']).toBe('same-origin');
  });
});

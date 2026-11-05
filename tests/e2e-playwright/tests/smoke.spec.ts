import { expect, test } from '@playwright/test';

test.describe('CircleGuard smoke', () => {
  test('la aplicación web responde y sirve el shell', async ({ page }) => {
    const response = await page.goto('/');
    expect(response?.status()).toBeLessThan(400);
    await expect(page.locator('body')).not.toBeEmpty();
  });

  test('el healthcheck del proxy responde', async ({ request }) => {
    const response = await request.get('/healthz');
    expect(response.status()).toBe(200);
    expect(await response.text()).toContain('ok');
  });
});

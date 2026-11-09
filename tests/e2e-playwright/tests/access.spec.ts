import { expect, test } from '@playwright/test';
import { SESSION, mockQrToken, seedSession } from './support';

test.describe('Flujo 3: validación de acceso', () => {
  test('la pantalla principal emite el QR rotativo con la sesión del usuario', async ({ page }) => {
    await seedSession(page);

    const qrRequest = page.waitForRequest('**/api/v1/auth/qr/generate');
    await mockQrToken(page);
    await page.goto('/');

    const request = await qrRequest;
    expect(request.headers()['authorization']).toBe(`Bearer ${SESSION.token}`);
    await expect(page.getByText(/EXPIRES IN/).filter({ visible: true }).first()).toBeVisible();
    await expect(page.locator('svg').first()).toBeVisible();
  });

  test('el escáner de la puerta exige reautenticación y se desbloquea', async ({ page }) => {
    await seedSession(page);
    await mockQrToken(page);

    await page.goto('/scan');
    await expect(page.getByText('BIOMETRIC RE-AUTH REQUIRED')).toBeVisible();

    await page.getByText('UNLOCK SCANNER', { exact: true }).click();
    await expect(page.getByText('ALIGN QR CODE WITHIN FRAME')).toBeVisible();
  });

  test('sin sesión el acceso al escáner redirige al inicio de sesión', async ({ page }) => {
    await page.goto('/scan');
    await expect(page).toHaveURL(/\/login/);
    await expect(page.getByText('Welcome Back')).toBeVisible();
  });
});

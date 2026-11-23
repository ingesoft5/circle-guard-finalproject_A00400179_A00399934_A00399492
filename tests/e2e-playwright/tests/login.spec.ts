import { expect, test } from '@playwright/test';
import { SESSION, mockQrToken } from './support';

test.describe('Flujo 1: inicio de sesión', () => {
  test('credenciales válidas llevan a la pantalla principal', async ({ page }) => {
    await mockQrToken(page);
    await page.route('**/api/v1/auth/login', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ token: SESSION.token, anonymousId: SESSION.anonymousId }),
      }),
    );

    await page.goto('/login');
    await expect(page.getByText('Welcome Back')).toBeVisible();

    const loginRequest = page.waitForRequest('**/api/v1/auth/login');
    await page.getByPlaceholder('Username').fill('estudiante.e2e');
    await page.getByPlaceholder('Password').fill('clave-e2e');
    await page.getByText('SIGN IN', { exact: true }).click();

    const request = await loginRequest;
    expect(request.postDataJSON()).toEqual({ username: 'estudiante.e2e', password: 'clave-e2e' });

    await expect(page.getByText(/EXPIRES IN/).filter({ visible: true }).first()).toBeVisible();

    const stored = await page.evaluate(() => window.localStorage.getItem('circleguard_token'));
    expect(stored).toBe(SESSION.token);
  });

  test('credenciales inválidas muestran el error y no abren sesión', async ({ page }) => {
    await page.route('**/api/v1/auth/login', (route) =>
      route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({ message: 'Bad credentials' }),
      }),
    );

    await page.goto('/login');
    const dialog = page.waitForEvent('dialog');
    await page.getByPlaceholder('Username').fill('estudiante.e2e');
    await page.getByPlaceholder('Password').fill('incorrecta');
    await page.getByText('SIGN IN', { exact: true }).click();

    const alert = await dialog;
    expect(alert.message()).toContain('[401]');
    await alert.dismiss();

    await expect(page).toHaveURL(/\/login/);
    const stored = await page.evaluate(() => window.localStorage.getItem('circleguard_token'));
    expect(stored).toBeNull();
  });
});

import { Page } from '@playwright/test';

export const SESSION = {
  anonymousId: 'e2e-anon-0001',
  token: 'e2e-jwt-token',
};

export async function seedSession(page: Page) {
  await page.addInitScript((session) => {
    window.localStorage.setItem('circleguard_anon_id', session.anonymousId);
    window.localStorage.setItem('circleguard_token', session.token);
  }, SESSION);
}

export async function mockQrToken(page: Page) {
  await page.route('**/api/v1/auth/qr/generate', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ qrToken: 'e2e-qr-token', expiresIn: '60' }),
    }),
  );
}

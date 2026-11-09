import { expect, test } from '@playwright/test';
import { SESSION, mockQrToken, seedSession } from './support';

const QUESTIONNAIRE = {
  id: 'e2e-questionnaire',
  title: 'Reporte de salud diario',
  description: 'Responda antes de ingresar al campus.',
  questions: [
    { id: 'q-fever', text: '¿Tiene fiebre?', type: 'YES_NO' },
    { id: 'q-contact', text: '¿Tuvo contacto con un caso confirmado?', type: 'YES_NO' },
  ],
};

test.describe('Flujo 2: cuestionario de salud', () => {
  test('carga el cuestionario activo y envía el reporte', async ({ page }) => {
    await seedSession(page);
    await mockQrToken(page);
    await page.route('**/api/v1/questionnaires/active', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(QUESTIONNAIRE),
      }),
    );
    await page.route('**/api/v1/surveys', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ id: 'e2e-survey' }),
      }),
    );

    await page.goto('/questionnaire');
    await expect(page.getByText('Health Screening')).toBeVisible();
    await expect(page.getByText(QUESTIONNAIRE.title)).toBeVisible();
    await expect(page.getByText('¿Tiene fiebre?')).toBeVisible();
    await expect(page.getByText('¿Tuvo contacto con un caso confirmado?')).toBeVisible();

    await page.getByText('NO', { exact: true }).first().click();

    const surveyRequest = page.waitForRequest('**/api/v1/surveys');
    await page.getByText('SUBMIT REPORT', { exact: true }).click();

    const request = await surveyRequest;
    expect(request.method()).toBe('POST');
    expect(request.postDataJSON().anonymousId).toBe(SESSION.anonymousId);

    await expect(page.getByText(/EXPIRES IN/).filter({ visible: true }).first()).toBeVisible();
  });

  test('sin cuestionario activo informa al usuario', async ({ page }) => {
    await seedSession(page);
    await mockQrToken(page);
    await page.route('**/api/v1/questionnaires/active', (route) =>
      route.fulfill({ status: 404, contentType: 'application/json', body: '{}' }),
    );

    await page.goto('/questionnaire');
    await expect(page.getByText('No active health survey available.')).toBeVisible();
  });
});

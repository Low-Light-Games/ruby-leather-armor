const { test, expect } = require('@playwright/test');
const { login } = require('../support/auth');

test.describe('Free user custom character drafts', () => {
  test('restores a local draft after a blocked save attempt', async ({ page }) => {
    await login(page, 'user');
    await page.goto('/sheets');
    await page.waitForLoadState('networkidle');

    await page.locator('#character-name').fill('Draft Hero');
    await page.locator('#character-description').fill('A custom character saved only in this browser.');

    await page.getByRole('button', { name: 'Save Sheet' }).click();

    await expect(page.locator('.flash-toast')).toContainText(
      'We kept this character as a local draft in this browser.',
    );

    await page.reload();
    await page.waitForLoadState('networkidle');

    await expect(page.locator('#character-name')).toHaveValue('Draft Hero');
    await expect(page.locator('#character-description')).toHaveValue(
      'A custom character saved only in this browser.',
    );
    await expect(page.locator('.flash-toast')).toContainText(
      'We restored your last custom character draft from this browser.',
    );
  });
});

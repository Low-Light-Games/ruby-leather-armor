const { test, expect } = require('@playwright/test');
const { login, createAdventure } = require('../support/auth');

async function submitFirstPendingRoll(page) {
  await page.locator('.roll-btn.roll-d20').first().click();

  const dialog = page.getByRole('dialog');
  await dialog.waitFor({ state: 'visible', timeout: 5_000 });
  await dialog.getByRole('button', { name: /close/i }).click();
  await dialog.waitFor({ state: 'hidden', timeout: 5_000 });

  await expect(page.locator('.roll-submit-btn')).toBeEnabled({ timeout: 5_000 });
  await page.locator('.roll-submit-btn').click();
}

test.describe('Pending roll refresh and resume', () => {
  test.beforeEach(async ({ page }) => {
    await login(page, 'admin');
    await page.goto('/admin/dm_config');
    await page.waitForLoadState('networkidle');
    await page.locator('input[name="action_queue"][value="progressive"]').check();
    await page.getByRole('button', { name: /save settings/i }).click();
    await page.waitForLoadState('networkidle');

    await page.goto('/adventures/new');
    await createAdventure(page);
  });

  test('restores pending rolls after reload and resumes the adventure', async ({ page }) => {
    const input = page.locator('.chat-input');
    await expect(input).toBeVisible({ timeout: 10_000 });

    await input.fill('I scout the corridor and pick the lock and push the door open');
    await page.locator('.chat-send-btn').click();

    const rollRequest = page.locator('.msg-type-roll_request');
    await expect(rollRequest).toBeVisible({ timeout: 20_000 });
    await expect(page.locator('.roll-submit-area')).toBeVisible({ timeout: 10_000 });

    await page.reload();
    await page.waitForLoadState('networkidle');

    await expect(page.locator('.roll-submit-area')).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('.roll-entry')).toHaveCount(1, { timeout: 10_000 });
    await expect(page.locator('.msg-type-roll_request')).toBeVisible({ timeout: 10_000 });

    await submitFirstPendingRoll(page);

    await expect(page.locator('.msg-thinking')).not.toBeVisible({ timeout: 20_000 });
    await expect(page.locator('.roll-submit-area')).not.toBeVisible({ timeout: 20_000 });

    const narrativeMessages = page.locator('.chat-message.msg-dm.msg-type-narrative');
    await expect(narrativeMessages).toHaveCount(3, { timeout: 20_000 });
    await expect(narrativeMessages.last()).toContainText(
      'The adventurer moves with purpose through the dungeon.',
      { timeout: 20_000 },
    );
  });
});

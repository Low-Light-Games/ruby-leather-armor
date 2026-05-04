const { test, expect } = require('@playwright/test');
const { login, createAdventure } = require('../support/auth');

test.describe('Adventure play happy path', () => {
  test.beforeEach(async ({ page }) => {
    await login(page, 'user');
    await createAdventure(page);
  });

  test('player can send a basic action and receive a GM response', async ({ page }) => {
    const input = page.locator('.chat-input');
    await expect(input).toBeVisible({ timeout: 10_000 });

    await input.fill('I look around the room.');
    await page.locator('.chat-send-btn').click();

    await expect(
      page.locator('.chat-message.msg-player').last()
    ).toContainText('I look around the room.', { timeout: 10_000 });

    const narrativeMessages = page.locator('.chat-message.msg-dm.msg-type-narrative');
    await expect(narrativeMessages).toHaveCount(2, { timeout: 20_000 });
    await expect(narrativeMessages.last()).toContainText(
      'The adventurer moves with purpose through the dungeon.',
      { timeout: 20_000 },
    );

    await expect(input).toBeEnabled({ timeout: 10_000 });
  });
});

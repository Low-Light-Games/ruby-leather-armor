const { test, expect } = require('@playwright/test');
const { login, beginAdventure } = require('../support/auth');
const { forceMaxRoll, sendChatMessage } = require('../support/chat');
const { submitActiveRollPanel } = require('../support/rolls');

// Walking 8 hours through the Bloodfield March story should:
//   1. Trigger Harbinger (encounter table is dense).
//   2. Pause for an initiative roll.
//   3. Initialize combat, render combat HUD + grid after rolling 20.

test.describe('Walk-into-combat — live OpenAI', () => {
  test('walking 8 hours triggers initiative; rolling 20 starts combat with grid', async ({ page }) => {
    test.setTimeout(300_000);

    await forceMaxRoll(page);
    await login(page, 'paid');
    await beginAdventure(page);

    await sendChatMessage(page, 'I walk around aimlessly for 8 hours');
    await submitActiveRollPanel(page);

    await expect(page.locator('.combat-hud')).toBeVisible({ timeout: 180_000 });
    await expect(page.locator('.combat-grid')).toBeVisible({ timeout: 30_000 });
  });
});

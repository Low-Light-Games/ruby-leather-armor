const { test, expect } = require('@playwright/test');
const { login, createAdventure } = require('../support/auth');

// Single live-OpenAI scenario:
//   1. Log in as a paid user.
//   2. Start a fresh adventure in the seeded "Bloodfield March" story
//      (which has an encounter table).
//   3. Send "I walk for 8 hours" — the journey-time estimator should fire
//      an encounter, surfacing an initiative roll request.
//   4. Force the d20 to land on 20 (predictability) and submit; assert
//      that the combat HUD/grid renders.
//
// Built incrementally — each step is added only after the previous one
// passes against real OpenAI through the e2e Docker stack.

test.describe('Walk-into-combat — live OpenAI', () => {
  test('walking 8 hours triggers initiative; rolling 20 starts combat with grid', async ({ page }) => {
    // Force d20 deterministically: Math.floor(0.999 * 20) + 1 = 20.
    // Init scripts run on every page load, so this stays in effect across
    // login/createAdventure navigations.
    await page.addInitScript(() => { Math.random = () => 0.999; });

    await login(page, 'paid');
    await createAdventure(page);

    const input = page.locator('.chat-input');
    await expect(input).toBeVisible({ timeout: 30_000 });

    await input.fill('I walk around aimlessly for 8 hours');
    await page.locator('.chat-send-btn').click();

    // Time estimator → Harbinger fires an encounter against Bloodfield March's
    // encounter table → UI mounts PendingInitiativePanel.
    const initiativePanel = page.locator('.roll-submit-area', {
      has: page.locator('.roll-prompt-header', { hasText: /Roll for Initiative/i }),
    });
    await expect(initiativePanel).toBeVisible({ timeout: 120_000 });

    // Click the d20 — Math.random override means natural=20, and the button
    // both rolls and submits in one action (see PendingInitiativePanel).
    await initiativePanel.locator('.roll-btn.roll-d20').click();

    // Combat initializes; the HUD (sidebar) and the battlefield grid render.
    await expect(page.locator('.combat-hud')).toBeVisible({ timeout: 90_000 });
    await expect(page.locator('.combat-grid')).toBeVisible({ timeout: 30_000 });
  });
});

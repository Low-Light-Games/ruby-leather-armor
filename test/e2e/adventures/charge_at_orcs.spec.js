const { test, expect } = require('@playwright/test');
const { login, beginAdventure } = require('../support/auth');
const { forceMaxRoll, sendChatMessage } = require('../support/chat');
const { submitActiveRollPanel } = require('../support/rolls');

// Charge → attack roll → 20 hits → combat starts proper.
//
// On gpt-5-nano + gpt-4.1-nano (the current roll-request / context-update
// models) this is currently flaky: RollRequest sometimes returns
// roll.skill=Initiative or a hallucinated skill, the post-roll
// combat-context-update sometimes rejects the AI-named participant on
// missing creature_sheet_id ("Combat context update dropped
// creature_sheet_id for orc patrol"). The deterministic regression for
// the sheet-id surface lives in test/e2e/adventures/attack_envoy.spec.js;
// this spec asserts the *desired* end state (an attack-style roll
// followed by a hit and combat HUD) so that AI improvements upstream
// flip it green.

test.describe('Charge at orc patrol — live OpenAI', () => {
  test('charging an unintroduced enemy → attack roll → hits → combat starts', async ({ page }) => {
    await forceMaxRoll(page);
    await login(page, 'paid');
    await beginAdventure(page);

    await sendChatMessage(page, 'I charge at the orc patrol');
    await submitActiveRollPanel(page, { typeMatch: /Attack/i });

    const hitMessage = page.locator('.chat-message', {
      hasText: /(hit|damage|wound|strike|HP)/i,
    });
    await expect(hitMessage.first()).toBeVisible({ timeout: 90_000 });

    await expect(page.locator('.combat-hud')).toBeVisible({ timeout: 60_000 });
  });
});

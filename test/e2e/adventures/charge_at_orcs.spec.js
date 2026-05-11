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
// missing actor_sheet_id ("Combat context update dropped
// actor_sheet_id for orc patrol"). The deterministic regression for
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

    // The DM narrates the attack outcome as an `action_result` message
    // before the engine prompts for initiative. The narrative wording
    // is AI-driven and varies turn to turn ("strikes true", "lands a
    // blow", "the dagger bites home"...), so assert on the message
    // *type* rather than fishing for keywords like /hit|damage/.
    const actionResult = page.locator('.chat-message.msg-type-action_result');
    await expect(actionResult.first()).toBeVisible({ timeout: 90_000 });

    await submitActiveRollPanel(page);

    await expect(page.locator('.combat-hud')).toBeVisible({ timeout: 60_000 });
  });
});

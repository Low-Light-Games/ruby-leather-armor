const { test, expect } = require('@playwright/test');
const { login, beginAdventure } = require('../support/auth');
const { forceMaxRoll, sendChatMessage } = require('../support/chat');
const { submitActiveRollPanel } = require('../support/rolls');

// Stab a named StoryNpc → attack roll → hit → initiative → combat starts.
//
// Seed story: "The Envoy's Gambit" (db/seeds/envoys_gambit_story.rb) drops
// the player into a sealed audience chamber opposite the named antagonist
// "Lord Velkar Mhonn", so lore retrieval surfaces him in the AI's context
// and combat_combatants carries his name verbatim (the orcs scenario's
// {name:, count:} → ['name'] mangling does not apply).
//
// Expected flow:
//   1. Player attacks → RollRequest emits an attack roll vs Velkar's AC.
//   2. Player rolls 20, hits, narrative confirms the strike landed.
//   3. Stagehand Path B fires Warmaster.initialize_from_names!, which
//      pauses for an initiative roll.
//   4. Player rolls initiative; combat HUD renders.
//
// Currently flaky against gpt-5-nano + gpt-4.1-nano: RollRequest
// sometimes returns Initiative directly, combat-context-update sometimes
// rejects the named participant on missing creature_sheet_id, or the
// pipeline auto-resolves the attack as a non-roll narrative outcome.
// Asserting the *desired* end state so AI improvements upstream flip
// the spec green.

test.describe("The Envoy's Gambit — live OpenAI", () => {
  test('attacking a named StoryNpc → attack roll → hit → initiative → combat starts', async ({ page }) => {
    await forceMaxRoll(page);
    await login(page, 'paid');
    await beginAdventure(page, { story: /Envoy's Gambit/i });

    await sendChatMessage(page, 'I attack Lord Velkar Mhonn with my dagger.');
    await submitActiveRollPanel(page, { typeMatch: /Attack/i });

    const hitMessage = page.locator('.chat-message', {
      hasText: /(hit|damage|wound|strike|HP)/i,
    });
    await expect(hitMessage.first()).toBeVisible({ timeout: 90_000 });

    await submitActiveRollPanel(page);

    await expect(page.locator('.combat-hud')).toBeVisible({ timeout: 60_000 });
  });
});

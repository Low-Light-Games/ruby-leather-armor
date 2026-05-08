const { test, expect } = require('@playwright/test');
const { login, beginAdventure } = require('../support/auth');
const { forceMaxRoll, sendChatMessage } = require('../support/chat');
const { submitActiveRollPanel } = require('../support/rolls');

// Regression lock for "I attack a named StoryNpc mid-conversation".
//
// Seed story: "The Envoy's Gambit" (db/seeds/envoys_gambit_story.rb)
//   - sealed audience chamber
//   - one antagonist StoryNpc named "Lord Velkar Mhonn"
//   - opening message drops the player mid-confrontation, knife on knee
//
// The named StoryNpc surfaces through lore retrieval into the AI's
// context, so the AI emits "Lord Velkar Mhonn" verbatim into
// combat_combatants (the orcs scenario's `["name"]` mangling does not
// happen here). After the player rolls, the post-roll narrative-phase
// fan-out runs combat-context-update against the freshly-named Velkar
// participant; the AI emits Velkar without a creature_sheet_id, and
// Steps::ContextUpdate#repair_participant_identity raises:
//   Ai::Error("Combat context update dropped creature_sheet_id for
//             Lord Velkar Mhonn")
// which Pipeline::Messenger renders as a system message:
//   "The Dungeon Master is momentarily distracted… (<error.message>)"
//
// The day combat-context-update tolerates the dropped sheet_id (or
// Warmaster pre-populates it before the fan-out), this assertion flips
// and the spec needs to be rewritten for the happy path.

test.describe("The Envoy's Gambit — live OpenAI", () => {
  test('regression: attacking a named StoryNpc surfaces the dropped creature_sheet_id error', async ({ page }) => {
    await forceMaxRoll(page);
    await login(page, 'paid');
    await beginAdventure(page, { story: /Envoy's Gambit/i });

    await sendChatMessage(page, 'I attack Lord Velkar Mhonn with my dagger.');
    await submitActiveRollPanel(page);

    const droppedSheetIdMessage = page.locator('.chat-message', {
      hasText: /dropped creature_sheet_id/i,
    });
    await expect(droppedSheetIdMessage).toBeVisible({ timeout: 120_000 });
  });
});

const { test, expect } = require('@playwright/test');
const { login, createAdventure } = require('../support/auth');

// Charge → attack roll → 20 hits → combat starts proper.
//
// LEFT AS A REGRESSION FLAG (currently failing):
//
//   On observed runs against gpt-4.1-nano + gpt-5-nano (roll-request steps),
//   the pipeline does NOT emit an attack-roll request for "I charge at the
//   orc patrol". Two things go wrong:
//
//     1. Ruling returns roll.type=combat / roll.skill=Initiative — i.e. an
//        initiative roll, not an attack roll. So this test's `/Attack/i`
//        match never fires.
//     2. Even if we accepted that, the combat-context-update step then
//        fails with "(Combat context update dropped creature_sheet_id for
//        orc patrol)" — combat aborts before initializing because the
//        AI-named NPC ("Orc Patrol") has no resolved creature_sheet.
//
//   Both behaviors are real pipeline issues worth fixing upstream. Until
//   then, the test stands as a regression alert.
//
// We force d20 = 20 via Math.random override. The pipeline then has to:
//   1. Emit an attack roll request (rollResolver labels it "Melee Attack" /
//      "Ranged Attack" / "Melee Touch Attack" / "Ranged Touch Attack").
//   2. Accept the roll, register a hit on the AI-named "Orc Patrol"
//      combatant, and surface that hit in the chat log.
//   3. Initialize combat (combat-hud renders).

test.describe('Charge at orc patrol — live OpenAI', () => {
  test('charging an unintroduced enemy → attack roll → hits → combat starts', async ({ page }) => {
    await page.addInitScript(() => { Math.random = () => 0.999; }); // d20 = 20
    await login(page, 'paid');
    await createAdventure(page);

    const input = page.locator('.chat-input');
    await expect(input).toBeVisible({ timeout: 30_000 });

    await input.fill('I charge at the orc patrol');
    await page.locator('.chat-send-btn').click();

    // Wait for an attack-type roll specifically (not Tumble or any other
    // pre-combat skill check). Asserting on the resolved roll-prompt-type
    // label keeps us robust to small AI variation in attack mode (melee /
    // melee touch / ranged / etc. all match /Attack/).
    const attackPanel = page.locator('.roll-submit-area', {
      has: page.locator('.roll-prompt-type', { hasText: /Attack/i }),
    });
    await expect(attackPanel).toBeVisible({ timeout: 120_000 });

    // Roll the d20 (natural 20 thanks to Math.random override). PendingRollsPanel
    // pops a "Dice roll result" dialog after rolling that blocks the Submit
    // Roll button until dismissed — different from PendingInitiativePanel,
    // which auto-submits.
    await attackPanel.locator('.roll-btn.roll-d20').click();
    const diceDialog = page.getByRole('dialog');
    await diceDialog.waitFor({ state: 'visible', timeout: 10_000 });
    await diceDialog.getByRole('button', { name: /close/i }).click();
    await diceDialog.waitFor({ state: 'hidden', timeout: 10_000 });

    const submitBtn = attackPanel.locator('.roll-submit-btn');
    await expect(submitBtn).toBeEnabled({ timeout: 10_000 });
    await submitBtn.click();

    // A hit registers as an action_result / damage line in the chat. Match
    // any of the words the renderer uses for impact reporting.
    const hitMessage = page.locator('.chat-message', {
      hasText: /(hit|damage|wound|strike|HP)/i,
    });
    await expect(hitMessage.first()).toBeVisible({ timeout: 90_000 });

    // Combat actually initializes: the HUD renders.
    await expect(page.locator('.combat-hud')).toBeVisible({ timeout: 60_000 });
  });
});

const { test, expect } = require('@playwright/test');
const { login, beginAdventure } = require('../support/auth');
const { forceMaxRoll, sendChatMessage } = require('../support/chat');
const { submitActiveRollPanel } = require('../support/rolls');

// "The Long Road" seeded story: paid user starts at Sailspar Docks; the only
// other location is Lighthouse Isle, ~1 km of open water away. The player
// swims across; we assert (a) the pipeline asks for a Swim skill check and
// (b) after a successful swim (forced d20=20), an arrival narrative mentions
// the destination — a rough proxy for current_location updating.

test.describe('Swim to Lighthouse Isle — live OpenAI', () => {
  test('paid user starts on Docks, swims, hits a Swim check, lands on the Isle', async ({ page }) => {
    await forceMaxRoll(page);
    await login(page, 'paid');
    await beginAdventure(page, { story: /Long Road/i });

    await sendChatMessage(page, 'I swim from the Sailspar Docks to the Lighthouse Isle');
    await submitActiveRollPanel(page, { typeMatch: /Swim/i });

    // Pipeline finishes processing the resolved roll.
    await expect(page.locator('.msg-thinking')).not.toBeVisible({ timeout: 120_000 });

    // Arrival proxy: the latest DM narrative should mention Lighthouse Isle.
    const narratives = page.locator('.chat-message.msg-dm.msg-type-narrative');
    await expect(narratives.last()).toContainText(/lighthouse/i, { timeout: 30_000 });
  });
});

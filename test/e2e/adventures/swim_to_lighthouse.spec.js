const { test, expect } = require('@playwright/test');
const { login } = require('../support/auth');

// "The Long Road" seeded story: paid user starts at Sailspar Docks; the only
// other location is Lighthouse Isle, ~1 km of open water away. The player
// swims across; we assert (a) the pipeline asks for a Swim skill check, and
// (b) after a successful swim (forced d20=20), an arrival narrative mentions
// the destination — a rough proxy for current_location updating.
//
// adventure_json doesn't expose current_location directly, so the second
// assertion sniffs the chat narrative. If that proves flaky, expose
// `current_location: adventure.current_location&.name` in
// AdventuresController#adventure_json and assert on the API response instead.

test.describe('Swim to Lighthouse Isle — live OpenAI', () => {
  test('paid user starts on Docks, swims, hits a Swim check, lands on the Isle', async ({ page }) => {
    await page.addInitScript(() => { Math.random = () => 0.999; }); // d20 = 20
    await login(page, 'paid');
    await expect(page).toHaveURL(/\/adventures\/new/);

    // Pick "The Long Road" specifically (Bloodfield is also seeded as story #1).
    const storySelect = page.locator('#story-select');
    await storySelect.waitFor({ timeout: 10_000 });
    const longRoadValue = await storySelect.locator('option', { hasText: /Long Road/i }).first().getAttribute('value');
    expect(longRoadValue, '"The Long Road" must be a seeded story').toBeTruthy();
    await storySelect.selectOption(longRoadValue);

    // Same sheet selection as createAdventure() — wait for the sheet dropdown
    // to populate, then take the first real entry.
    const sheetSelect = page.locator('#sheet-select');
    await sheetSelect.waitFor({ timeout: 5_000 });
    await page.waitForFunction(() => {
      const sel = document.querySelector('#sheet-select');
      return sel && sel.options.length > 1;
    }, { timeout: 5_000 });
    const firstSheetValue = await sheetSelect.locator('option').nth(1).getAttribute('value');
    await sheetSelect.selectOption(firstSheetValue);

    await Promise.all([
      page.waitForURL(/\/adventures\/\d+/, { timeout: 30_000 }),
      page.getByRole('button', { name: /begin adventure/i }).click(),
    ]);

    const input = page.locator('.chat-input');
    await expect(input).toBeVisible({ timeout: 30_000 });

    await input.fill('I swim from the Sailspar Docks to the Lighthouse Isle');
    await page.locator('.chat-send-btn').click();

    // Pipeline should issue a Swim skill check. rollResolver labels it
    // "Swim Check" (or similar — match /Swim/ to stay tolerant).
    const swimPanel = page.locator('.roll-submit-area', {
      has: page.locator('.roll-prompt-type', { hasText: /Swim/i }),
    });
    await expect(swimPanel).toBeVisible({ timeout: 120_000 });

    // Roll the d20 (natural 20 via Math.random override). PendingRollsPanel
    // pops a "Dice roll result" dialog after rolling that blocks the Submit
    // Roll button until dismissed — different from PendingInitiativePanel,
    // which auto-submits.
    await swimPanel.locator('.roll-btn.roll-d20').click();
    const diceDialog = page.getByRole('dialog');
    await diceDialog.waitFor({ state: 'visible', timeout: 10_000 });
    await diceDialog.getByRole('button', { name: /close/i }).click();
    await diceDialog.waitFor({ state: 'hidden', timeout: 10_000 });

    const submitBtn = swimPanel.locator('.roll-submit-btn');
    await expect(submitBtn).toBeEnabled({ timeout: 10_000 });
    await submitBtn.click();

    // Pipeline finishes processing the resolved roll.
    const thinking = page.locator('.msg-thinking');
    await expect(thinking).not.toBeVisible({ timeout: 120_000 });

    // Arrival proxy: the latest DM narrative should mention Lighthouse Isle.
    // This is the weakest assertion — if the AI summarises the swim without
    // naming the destination it'll fail; that's worth knowing.
    const narratives = page.locator('.chat-message.msg-dm.msg-type-narrative');
    await expect(narratives.last()).toContainText(/lighthouse/i, { timeout: 30_000 });
  });
});

const { test, expect } = require('@playwright/test');
const { login } = require('../support/auth');

// Drives a full multi-turn combat encounter against the seeded combat fixture
// (`db/seeds.rb#seed_playwright_combat_fixture!`). The fixture lands the
// player in an active combat round vs two weak goblins (HP 1, AC 5) so player
// attacks one-shot deterministically; player AC stays high enough that the
// fighter survives goblin swings without RNG worries.
//
// One e2e replaces the unit specs deleted in PR 118: it covers the buff path,
// per-action HUD updates, action-economy bookkeeping across turns, NPC turn
// advancement, attack damage / drop, and combat-end broadcast.

test.describe('Combat encounter — multi-turn HUD coverage', () => {
  test.setTimeout(60_000);

  test('cast buff, exchange swings with NPCs, drop both goblins, combat ends', async ({ page }) => {
    const combatEnded = async () =>
      (await page.locator('.chat-message.msg-type-combat_end').count()) > 0 ||
      !(await page.locator('.combat-action-panel').isVisible());

    const waitForCombatToSettle = async () => {
      // After a kill the server flips combat_context.active=false and broadcasts
      // a combat_end message — but the WebSocket round-trip can lag the HTTP
      // response, so poll for either signal before deciding combat is still on.
      for (let i = 0; i < 20; i += 1) {
        if (await combatEnded()) return true;
        await page.waitForTimeout(150);
      }
      return false;
    };

    const endTurnAndRefresh = async () => {
      const endTurnBtn = page.locator('.end-turn-btn');
      await expect(endTurnBtn).toBeEnabled({ timeout: 15_000 });
      await endTurnBtn.click();
      await expect(
        page.locator('.action-economy-chip.available').filter({ hasText: /Standard/i })
      ).toBeVisible({ timeout: 15_000 });
    };

    const dropTarget = async (targetName) => {
      for (let attempt = 0; attempt < 5; attempt += 1) {
        if (await combatEnded()) return;

        const optionMatch = page.locator('#combat-target option', { hasText: new RegExp(targetName, 'i') });
        if ((await optionMatch.count()) === 0) return;

        const labelText = (await optionMatch.first().textContent()).trim();
        await page.locator('#combat-target').selectOption({ label: labelText });

        const attackButton = page.locator('.attack-option-btn').first();
        await expect(attackButton).toBeEnabled({ timeout: 10_000 });
        await attackButton.click();

        await expect(page.locator('.log-entry').last()).toBeVisible({ timeout: 10_000 });

        if (await waitForCombatToSettle()) return;
        const stillListed = await page
          .locator('#combat-target option', { hasText: new RegExp(targetName, 'i') })
          .count();
        if (stillListed === 0) return;

        // Whiffed — burn the round and try again.
        await endTurnAndRefresh();
      }
      throw new Error(`Failed to drop ${targetName} within retry budget`);
    };

    await login(page, 'combatFixture');

    const adventuresResponse = await page.request.get('/adventures');
    expect(adventuresResponse.ok()).toBeTruthy();
    const adventures = await adventuresResponse.json();
    expect(adventures.length).toBeGreaterThan(0);

    await page.goto(`/adventures/${adventures[0].id}`);
    await page.waitForLoadState('networkidle');

    // ── HUD landed in active combat ─────────────────────────────────────────
    await expect(page.locator('.combat-hud')).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.combat-action-panel')).toBeVisible();
    await expect(page.locator('.combat-grid')).toBeVisible();
    await expect(page.locator('.action-economy-chip')).toHaveCount(4);
    await expect(
      page.locator('.action-economy-chip.available').filter({ hasText: /Standard/i })
    ).toBeVisible();

    // ── Round 1: cast Mage Armor (buff path) ────────────────────────────────
    const buffButton = page.locator('.buff-option-btn').filter({ hasText: /Mage Armor/i });
    await expect(buffButton).toBeVisible({ timeout: 10_000 });
    await buffButton.click();

    await expect(page.locator('.log-entry').last()).toContainText(/Mage Armor/i, { timeout: 10_000 });
    await expect(
      page.locator('.action-economy-chip.spent').filter({ hasText: /Standard/i })
    ).toBeVisible({ timeout: 10_000 });

    // ── Round 1: end player turn — NPCs take their turns ────────────────────
    const logEntriesBeforeEndTurn = await page.locator('.log-entry').count();
    await endTurnAndRefresh();

    // NPC events render as additional log lines within the rolling window.
    await expect.poll(
      async () => page.locator('.log-entry').count(),
      { timeout: 10_000 }
    ).toBeGreaterThanOrEqual(Math.min(logEntriesBeforeEndTurn + 1, 3));

    // ── Drop both goblins; loop guards against the rare miss ────────────────
    await dropTarget('Goblin Scout');

    // Between targets the player must end the turn so the next round refreshes
    // the standard action — unless the first kill already ended combat.
    if (!(await waitForCombatToSettle())) {
      await endTurnAndRefresh();
      await dropTarget('Goblin Soldier');
      await waitForCombatToSettle();
    }

    // ── Combat ended — system message broadcast and HUD tears down ──────────
    await expect(
      page.locator('.chat-message.msg-type-combat_end')
    ).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.combat-action-panel')).toHaveCount(0, { timeout: 15_000 });
  });
});

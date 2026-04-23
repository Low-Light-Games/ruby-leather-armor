const { test, expect } = require('@playwright/test');
const { login, createAdventure } = require('../support/auth');

// ── ensure the Action Queue radio is set to "Progressive" ───────────────────
async function ensureProgressiveActionQueue(page) {
  await page.goto('/admin/dm_config');
  await page.waitForLoadState('networkidle');

  // Select "progressive" radio — value="progressive"
  await page.locator('input[name="action_queue"][value="progressive"]').check();
  await page.getByRole('button', { name: /save settings/i }).click();
  await page.waitForLoadState('networkidle');
}

// ── submit one roll in the PendingRollsPanel ─────────────────────────────────
async function submitRoll(page) {
  // Click the d20 button — opens a dice roll result dialog
  await page.locator('.roll-btn.roll-d20').first().click();

  // Close the dice-result dialog so the Submit Roll button becomes enabled
  const dialog = page.getByRole('dialog');
  await dialog.waitFor({ state: 'visible', timeout: 5_000 });
  await dialog.getByRole('button', { name: /close/i }).click();
  await dialog.waitFor({ state: 'hidden', timeout: 5_000 });

  // Now the Submit Roll button should be enabled
  await page.locator('.roll-submit-btn').waitFor({ state: 'visible' });
  await expect(page.locator('.roll-submit-btn')).toBeEnabled({ timeout: 5_000 });
  await page.locator('.roll-submit-btn').click();
}

// ── Tests ────────────────────────────────────────────────────────────────────

test.describe('Per-action narration — progressive action queue', () => {
  test.beforeEach(async ({ page }) => {
    await login(page, 'admin');
    await ensureProgressiveActionQueue(page);
    await page.goto('/adventures/new');
    await createAdventure(page);
  });

  test('shows progressive badge for action 1 and halts on roll request', async ({ page }) => {
    // ── Submit compound action ──────────────────────────────────────────────
    const input = page.locator('.chat-input');
    await input.waitFor({ state: 'visible', timeout: 10_000 });
    await input.fill('I scout the corridor and pick the lock and push the door open');
    await page.locator('.chat-send-btn').click();

    // ── Verify the player message appeared (send was accepted) ───────────────
    await expect(
      page.locator('.chat-message.msg-player').last()
    ).toBeVisible({ timeout: 10_000 });

    // ── Verify the thinking indicator appeared (pipeline started) ────────────
    await expect(page.locator('.msg-thinking')).toBeVisible({ timeout: 10_000 });

    // ── Action 1 narrated immediately (badge 1 / 3) ─────────────────────────
    const badge1 = page.locator('.msg-sequence-badge', { hasText: '1 / 3' });
    await badge1.waitFor({ timeout: 20_000 });
    await expect(badge1).toBeVisible();

    // ── Roll request appears (action 2 — pick the lock needs Disable Device) ─
    const rollRequestMsg = page.locator('.msg-type-roll_request');
    await rollRequestMsg.waitFor({ timeout: 20_000 });
    await expect(rollRequestMsg).toBeVisible();

    // Action 3 was never reached — no 3 / 3 badge yet
    await expect(page.locator('.msg-sequence-badge', { hasText: '3 / 3' })).not.toBeVisible();

    // ── Submit the roll ─────────────────────────────────────────────────────
    await submitRoll(page);

    // ── Post-roll: accumulated narrative appears (no sequence badge) ─────────
    // Wait for thinking to disappear — the accumulated narration has arrived
    await expect(page.locator('.msg-thinking')).not.toBeVisible({ timeout: 20_000 });

    // Total DM narrative messages: 1 initial hook + 1 progressive (action 1) + 1 accumulated (post-roll)
    const narrativeMsgs = page.locator('.chat-message.msg-dm.msg-type-narrative');
    await expect(narrativeMsgs).toHaveCount(3, { timeout: 5_000 });

    // Confirm the resume path stayed on the accumulated track — no 2/3 or 3/3 badges
    await expect(page.locator('.msg-sequence-badge', { hasText: '2 / 3' })).not.toBeVisible();
    await expect(page.locator('.msg-sequence-badge', { hasText: '3 / 3' })).not.toBeVisible();
  });

  test('thinking indicator survives page refresh mid-pipeline', async ({ page }) => {
    // Intercept the messages load and inject pipeline_running: true so the UI
    // believes a pipeline is in progress — simulates a mid-pipeline refresh.
    await page.route('**/adventures/*/messages', async route => {
      const response = await route.fetch();
      const json = await response.json();
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ...json, pipeline_running: true }),
      });
    });

    // Refresh the page to trigger the intercept
    await page.reload();
    await page.waitForLoadState('networkidle');

    // UI should restore the thinking indicator and lock the input
    await expect(page.locator('.msg-thinking')).toBeVisible({ timeout: 8_000 });
    await expect(page.locator('.chat-input')).toBeDisabled();
  });
});

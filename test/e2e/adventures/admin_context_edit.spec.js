// @ts-check
const { test, expect } = require('@playwright/test');
const { login } = require('../support/auth');

/**
 * Pre-condition: the seeded "Lake of Whispers" story and at least one
 * character sheet must exist in the database.
 *
 * Verifies that an admin can edit a micro context inline on the
 * adventure play page and that the change is persisted.
 */

async function createAdventure(page) {
  await page.goto('/adventures/new');
  // Wait for the React SPA to mount and data to load — the selects only
  // appear once the stories/sheets API calls have resolved.
  await page.locator('#story-select').waitFor();

  await page.locator('#story-select').selectOption({ label: 'The Lake of Whispers' });

  const firstSheetValue = await page
    .locator('#sheet-select option:not([value=""])')
    .first()
    .getAttribute('value');
  if (firstSheetValue) {
    await page.locator('#sheet-select').selectOption(firstSheetValue);
  }

  await Promise.all([
    page.waitForURL(/\/adventures\/\d+/),
    page.getByRole('button', { name: /begin adventure/i }).click(),
  ]);

  await page.waitForLoadState('networkidle');
}

test.describe('Admin inline context editing', () => {
  test('admin can edit a micro context from the play page', async ({ page }) => {
    await login(page, 'admin');
    await createAdventure(page);

    await expect(page).toHaveURL(/\/adventures\/\d+/);

    // ── Micro Contexts panel is admin-only ──────────────────────────
    const toggleBtn = page.locator('.context-debug-toggle');
    await expect(toggleBtn).toBeVisible();
    await toggleBtn.click();

    // ── Find the first active context's Edit button ─────────────────
    const editBtn = page.locator('.context-edit-btn').first();
    await expect(editBtn).toBeVisible();
    await editBtn.click();

    // ── Editor appears with textarea and Save / Cancel ──────────────
    const textarea = page.locator('.context-json-editor');
    await expect(textarea).toBeVisible();
    await expect(page.locator('.context-save-btn')).toBeVisible();
    await expect(page.locator('.context-cancel-btn')).toBeVisible();

    // ── Mutate the JSON ─────────────────────────────────────────────
    const originalJson = await textarea.inputValue();
    const parsed = JSON.parse(originalJson);
    parsed.__admin_test_marker = true;
    await textarea.fill(JSON.stringify(parsed, null, 2));

    // ── Save and wait for the PATCH response ────────────────────────
    await Promise.all([
      page.waitForResponse(
        res => res.url().includes('/admin/adventures/') && res.request().method() === 'PATCH'
      ),
      page.locator('.context-save-btn').click(),
    ]);

    // ── Editor should close; read-only view should be back ──────────
    await expect(textarea).not.toBeVisible();
    await expect(page.locator('.context-detail-list').first()).toBeVisible();
  });

  test('cancel discards changes without saving', async ({ page }) => {
    await login(page, 'admin');
    await createAdventure(page);

    await page.locator('.context-debug-toggle').click();

    const editBtn = page.locator('.context-edit-btn').first();
    await expect(editBtn).toBeVisible();
    await editBtn.click();

    const textarea = page.locator('.context-json-editor');
    await expect(textarea).toBeVisible();

    await page.locator('.context-cancel-btn').click();

    await expect(textarea).not.toBeVisible();
    await expect(page.locator('.context-detail-list').first()).toBeVisible();
  });

  test('non-admin does not see the Micro Contexts toggle', async ({ page }) => {
    await login(page, 'user');
    await createAdventure(page);

    await expect(page.locator('.context-debug-toggle')).not.toBeVisible();
  });
});

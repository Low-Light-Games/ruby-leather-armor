const { test, expect } = require('@playwright/test');
const { login, createAdventure } = require('../support/auth');

test.describe('Admin micro context inline edit', () => {
  test.beforeEach(async ({ page }) => {
    await login(page, 'admin');
    await createAdventure(page);
  });

  test('admin can edit a context and save', async ({ page }) => {
    // Open Micro Contexts panel
    await page.getByRole('button', { name: /micro contexts/i }).click();

    // Click Edit on first visible context
    const editBtn = page.locator('.context-edit-btn').first();
    await editBtn.waitFor({ timeout: 5_000 });
    await editBtn.click();

    // Editor should be visible
    const editor = page.locator('.context-json-editor').first();
    await expect(editor).toBeVisible();

    // Modify and save
    await editor.fill('{"test_key":"test_value"}');
    await page.locator('.context-save-btn').first().click();

    // Editor should close, read-only view returns
    await expect(editor).not.toBeVisible();
    await expect(page.locator('.context-entry').first()).toBeVisible();
  });

  test('saved context value persists after page reload', async ({ page }) => {
    await page.getByRole('button', { name: /micro contexts/i }).click();

    const editBtn = page.locator('.context-edit-btn').first();
    await editBtn.waitFor({ timeout: 5_000 });
    await editBtn.click();

    const editor = page.locator('.context-json-editor').first();
    await expect(editor).toBeVisible();

    const persistedValue = `persisted_${Date.now()}`;
    await editor.fill(`{"test_key":"${persistedValue}"}`);
    await page.locator('.context-save-btn').first().click();

    await expect(editor).not.toBeVisible();
    await page.reload();
    await page.waitForLoadState('networkidle');

    await page.getByRole('button', { name: /micro contexts/i }).click();
    await expect(page.locator('.context-entry')).toContainText(persistedValue, { timeout: 10_000 });
  });

  test('cancel discards changes', async ({ page }) => {
    await page.getByRole('button', { name: /micro contexts/i }).click();

    const editBtn = page.locator('.context-edit-btn').first();
    await editBtn.waitFor({ timeout: 5_000 });
    await editBtn.click();

    const editor = page.locator('.context-json-editor').first();
    await editor.fill('{"discarded":"yes"}');
    await page.locator('.context-cancel-btn').first().click();

    await expect(editor).not.toBeVisible();
    // Edit button is back
    await expect(editBtn).toBeVisible();
  });
});

test('non-admin has no edit button', async ({ page }) => {
  await login(page, 'user');
  await createAdventure(page);

  // If the toggle is even present, open it
  const toggle = page.locator('.context-debug-toggle');
  if (await toggle.isVisible()) {
    await toggle.click();
    await expect(page.locator('.context-edit-btn')).toHaveCount(0);
  }
});

const { test, expect } = require('@playwright/test');
const { login, createAdventure } = require('../support/auth');

test.describe('Character sidebar buffs and conditions', () => {
  test.beforeEach(async ({ page }) => {
    await login(page, 'user');
    await createAdventure(page);
  });

  test('shows conditions and an active buff row with readable target label', async ({ page }) => {
    const url = page.url();
    const m = url.match(/\/adventures\/(\d+)/);
    expect(m).toBeTruthy();
    const adventureId = m[1];

    const token = await page.locator('meta[name="csrf-token"]').getAttribute('content');
    expect(token).toBeTruthy();

    const res = await page.request.patch(`/adventures/${adventureId}/adventure_sheet`, {
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': token,
      },
      data: {
        conditions: ['shaken'],
        active_buffs: [
          {
            source: 'rage',
            source_type: 'class_ability',
            bonus_type: 'morale',
            target: 'strength',
            value: 2,
            expires_at_game_hours: null,
          },
        ],
      },
    });
    expect(res.ok()).toBeTruthy();

    await page.reload();
    await page.waitForLoadState('networkidle');

    await expect(page.locator('.condition-badge').first()).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.active-buffs-section')).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.active-buff-effect')).toContainText('STR');
  });
});

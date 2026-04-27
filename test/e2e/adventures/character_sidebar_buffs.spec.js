const { test, expect } = require('@playwright/test');
const { login } = require('../support/auth');

test.describe('Character sidebar buffs and conditions', () => {
  test('shows conditions and an active buff row with readable target label', async ({ page }) => {
    await login(page, 'sidebarFixture');

    const response = await page.request.get('/adventures');
    expect(response.ok()).toBeTruthy();
    const adventures = await response.json();
    expect(adventures).toHaveLength(1);

    await page.goto(`/adventures/${adventures[0].id}`);
    await page.waitForLoadState('networkidle');

    await expect(page.locator('.active-buffs-section')).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.active-buff-row')).toHaveCount(3);
    await expect(page.locator('.active-buff-effect').filter({ hasText: 'STR' })).toBeVisible();
    await expect(page.locator('.active-buff-source').filter({ hasText: 'mage_armor' })).toBeVisible();
    await expect(page.locator('.active-buff-source').filter({ hasText: 'fighting_defensively' })).toBeVisible();
    await expect(page.locator('.condition-badge')).toHaveCount(1);
    await expect(page.locator('.condition-badge').first()).toContainText('Shaken');
  });
});

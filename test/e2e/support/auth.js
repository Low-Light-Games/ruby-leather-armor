const CREDENTIALS = {
  admin: { email: 'admin@example.com', password: 'admin123' },
  user:  { email: 'test@example.com',  password: 'test123'  },
  sidebarFixture: { email: 'sidebar-fixture@example.com', password: 'sidebar123' },
  combatFixture:  { email: 'combat-fixture@example.com',  password: 'combat123'  },
};

async function login(page, role = 'user') {
  const { email, password } = CREDENTIALS[role];
  await page.goto('/adventures/new');
  await page.waitForLoadState('networkidle');

  const emailInput = page.locator('input[type="email"]');
  if (!(await emailInput.isVisible())) return; // already logged in

  await emailInput.fill(email);
  await page.locator('input[type="password"]').fill(password);
  await Promise.all([
    page.waitForResponse(res => res.url().includes('/login')),
    page.getByRole('button', { name: 'Login' }).click(),
  ]);
  await page.locator('#story-select').waitFor({ timeout: 10_000 });
}

// Selects the first available story and sheet, then clicks Begin Adventure.
// Always picks by position so it is independent of seed data ordering.
async function createAdventure(page) {
  const storySelect = page.locator('#story-select');
  await storySelect.waitFor({ timeout: 10_000 });
  const storyOptions = await storySelect.locator('option').all();
  const firstStoryValue = await storyOptions[1].getAttribute('value');
  await storySelect.selectOption(firstStoryValue);

  const sheetSelect = page.locator('#sheet-select');
  await sheetSelect.waitFor({ timeout: 5_000 });
  await page.waitForFunction(() => {
    const sel = document.querySelector('#sheet-select');
    return sel && sel.options.length > 1;
  }, { timeout: 5_000 });
  const sheetOptions = await sheetSelect.locator('option').all();
  const firstSheetValue = await sheetOptions[1].getAttribute('value');
  await sheetSelect.selectOption(firstSheetValue);

  await Promise.all([
    page.waitForURL(/\/adventures\/\d+/, { timeout: 30_000 }),
    page.getByRole('button', { name: /begin adventure/i }).click(),
  ]);
}

module.exports = { login, createAdventure, CREDENTIALS };

const { expect } = require('@playwright/test');

const CREDENTIALS = {
  admin: { email: 'admin@example.com', password: 'admin123' },
  user:  { email: 'test@example.com',  password: 'test123'  },
  paid:  { email: 'paid@example.com',  password: 'paid123'  },
  sidebarFixture: { email: 'sidebar-fixture@example.com', password: 'sidebar123' },
  combatFixture:  { email: 'combat-fixture@example.com',  password: 'combat123'  },
};

async function login(page, role = 'user') {
  const creds = CREDENTIALS[role];
  if (!creds) throw new Error(`Unknown role '${role}' — pick one of: ${Object.keys(CREDENTIALS).join(', ')}`);

  await page.goto('/adventures/new');
  await page.waitForLoadState('networkidle');

  const emailInput = page.locator('input[type="email"]');
  if (!(await emailInput.isVisible())) return; // already logged in

  await emailInput.fill(creds.email);
  await page.locator('input[type="password"]').fill(creds.password);
  await Promise.all([
    page.waitForResponse(res => res.url().includes('/login')),
    page.getByRole('button', { name: 'Login' }).click(),
  ]);
  await page.locator('#story-select').waitFor({ timeout: 10_000 });
}

// @param  page    Playwright Page
// @param  options { story, sheet } — both optional, can be string|RegExp.
//                 When omitted the first available option is used. The story
//                 selector skips position 0 (the placeholder); strings are
//                 treated as exact match, RegExps as case-insensitive search.
async function beginAdventure(page, { story, sheet } = {}) {
  await selectFirstOrMatching(page.locator('#story-select'), story, '#story-select');

  const sheetSelect = page.locator('#sheet-select');
  await sheetSelect.waitFor({ timeout: 5_000 });
  await page.waitForFunction(() => {
    const sel = document.querySelector('#sheet-select');
    return sel && sel.options.length > 1;
  }, { timeout: 5_000 });
  await selectFirstOrMatching(sheetSelect, sheet, '#sheet-select');

  await Promise.all([
    page.waitForURL(/\/adventures\/\d+/, { timeout: 30_000 }),
    page.getByRole('button', { name: /begin adventure/i }).click(),
  ]);
}

async function selectFirstOrMatching(selectLocator, matcher, debugLabel) {
  await selectLocator.waitFor({ timeout: 10_000 });
  const options = await selectLocator.locator('option').all();
  if (options.length <= 1) throw new Error(`${debugLabel} has no real options`);

  let optionValue;
  if (matcher == null) {
    optionValue = await options[1].getAttribute('value');
  } else {
    const optionLocator = selectLocator.locator('option', { hasText: matcher });
    optionValue = await optionLocator.first().getAttribute('value');
    expect(optionValue, `${debugLabel} option matching ${matcher} must exist`).toBeTruthy();
  }
  await selectLocator.selectOption(optionValue);
}

module.exports = { login, beginAdventure, CREDENTIALS };

const CREDENTIALS = {
  admin: { email: 'admin@example.com', password: 'admin123' },
  user:  { email: 'test@example.com',  password: 'test123'  },
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

module.exports = { login, CREDENTIALS };

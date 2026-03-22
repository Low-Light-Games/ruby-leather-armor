// @ts-check

const CREDENTIALS = {
  admin: { email: 'admin@example.com', password: 'admin123' },
  user:  { email: 'test@example.com',  password: 'test123' },
};

/**
 * Logs in via the email/password form. Navigates to /adventures/new which
 * renders the Login component when unauthenticated — the frontpage (/) is a
 * marketing page with no login form. After a successful login the same React
 * SPA re-renders showing the adventure creation form without a page reload.
 *
 * @param {import('@playwright/test').Page} page
 * @param {'admin' | 'user'} role
 */
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

  // Wait for the adventure creation form to appear, confirming auth succeeded
  await page.locator('#story-select').waitFor();
}

module.exports = { login, CREDENTIALS };

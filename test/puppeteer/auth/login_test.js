const {
  BASE_URL, CREDENTIALS, runSuite, setupPage, login,
  getBodyText, wait,
} = require('../support/helpers');

runSuite('Auth › Login & Credentials', async (browser, assert) => {
  const page = await setupPage(browser);

  // ── Unauthenticated user sees login form ──────────────────────────
  console.log('Unauthenticated user sees login form');
  await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 15000 });

  assert(await page.$('input[type="email"]') !== null, 'Login form has email input');
  assert(await page.$('input[type="password"]') !== null, 'Login form has password input');
  assert(await page.$('button[type="submit"]') !== null, 'Login form has submit button');

  // ── Login with invalid credentials shows error ────────────────────
  console.log('\nInvalid credentials show error');
  await page.type('input[type="email"]', 'wrong@example.com');
  await page.type('input[type="password"]', 'wrongpassword');
  await page.click('button[type="submit"]');
  await wait(2000);

  const pageText = await getBodyText(page);
  const hasError = pageText.toLowerCase().includes('invalid') ||
                   pageText.toLowerCase().includes('failed') ||
                   pageText.toLowerCase().includes('error');
  assert(hasError, 'Error message shown for invalid credentials');

  // ── Login with valid admin credentials ────────────────────────────
  console.log('\nAdmin login');
  await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 15000 });
  await page.type('input[type="email"]', CREDENTIALS.admin.email);
  await page.type('input[type="password"]', CREDENTIALS.admin.password);

  const csrfToken = await page.$eval(
    'meta[name="csrf-token"]', el => el.getAttribute('content')
  ).catch(() => null);
  assert(csrfToken !== null && csrfToken.length > 0, 'CSRF token is present');

  await Promise.all([
    page.waitForResponse(res => res.url().includes('login'), { timeout: 10000 }),
    page.click('button[type="submit"]'),
  ]);
  await wait(2000);

  const bodyAfterLogin = await getBodyText(page);
  const isLoggedIn = bodyAfterLogin.includes('Logged in as') ||
                     bodyAfterLogin.includes('admin@example.com');
  assert(isLoggedIn, 'Admin user is logged in');
  assert(await page.$('input[type="email"]') === null, 'Login form is no longer visible');

  // ── Admin sees admin section ──────────────────────────────────────
  console.log('\nAdmin-only content');
  const hasAdminView = bodyAfterLogin.toLowerCase().includes('admin') ||
                       bodyAfterLogin.toLowerCase().includes('all character sheets');
  assert(hasAdminView, 'Admin view is visible');
});

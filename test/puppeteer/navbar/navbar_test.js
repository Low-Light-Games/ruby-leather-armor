const {
  runSuite, setupPage, login,
  getBodyText, wait,
} = require('../support/helpers');

runSuite('Navbar › Elements & links', async (browser, assert) => {
  const page = await setupPage(browser);
  await login(page, 'user');

  // ── Elements present ──────────────────────────────────────────────
  console.log('Navbar elements on sheets page');
  assert(await page.$('a.nav-link[href="/"]') !== null, '"Sheets" link present');
  assert(await page.$('a.adventure-cta[href="/adventures/new"]') !== null, '"Adventure!" CTA present');
  assert(await page.$('.logout-button') !== null, 'Logout button present');

  const body = await getBodyText(page);
  assert(body.includes('Logged in as'), 'Shows logged-in user info');

  // ── Navbar on adventure creation page ─────────────────────────────
  console.log('\nNavbar on adventure creation page');
  await page.goto(`${require('../support/helpers').BASE_URL}/adventures/new`, {
    waitUntil: 'networkidle2', timeout: 15000,
  });
  await wait(2000);

  assert(await page.$('.app-header') !== null, 'Navbar present on /adventures/new');
  assert(await page.$('a.nav-link[href="/"]') !== null, '"Sheets" link present on /adventures/new');
  assert(await page.$('.logout-button') !== null, 'Logout button present on /adventures/new');
});

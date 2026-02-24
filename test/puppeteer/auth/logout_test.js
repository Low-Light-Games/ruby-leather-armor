const {
  runSuite, setupPage, login, logout,
  getBodyText, wait,
} = require('../support/helpers');

runSuite('Auth › Logout', async (browser, assert) => {
  const page = await setupPage(browser);

  // Login first
  await login(page, 'admin');

  // ── Logout ────────────────────────────────────────────────────────
  console.log('Logout returns to login form');
  const logoutClicked = await logout(page);
  assert(logoutClicked, 'Logout button found and clicked');
  assert(await page.$('input[type="email"]') !== null, 'Login form reappears after logout');
});

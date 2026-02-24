const {
  runSuite, setupPage, login,
  getBodyText, wait,
} = require('../support/helpers');

runSuite('Auth › Role-based access', async (browser, assert) => {
  const page = await setupPage(browser);

  // ── Regular user does NOT see admin section ───────────────────────
  console.log('Regular user has no admin view');
  await login(page, 'user');

  const body = await getBodyText(page);
  assert(
    body.includes('test@example.com') || body.includes('Logged in as'),
    'Regular user is logged in'
  );
  assert(
    !body.toLowerCase().includes('all character sheets'),
    'Regular user does not see "All Character Sheets" admin section'
  );
});

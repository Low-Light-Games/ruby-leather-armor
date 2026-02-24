const {
  runSuite, setupPage, login,
  getBodyText, clickButtonByText, hasButtonWithText, wait,
} = require('../support/helpers');

runSuite('Sheets › Editor UI', async (browser, assert) => {
  const page = await setupPage(browser, { acceptDialogs: true });
  await login(page, 'user');

  const bodyText = await getBodyText(page);

  // ── Form elements present ─────────────────────────────────────────
  console.log('Editor form elements');
  assert(bodyText.includes('Character Name'), 'Has character name label');
  assert(await page.$('#character-description') !== null, 'Has description textarea');
  assert(bodyText.includes('Points spent:') && bodyText.includes('/ 27'), 'Shows point counter');

  assert(await hasButtonWithText(page, 'Save Sheet'), 'Has "Save Sheet" button');
  assert(await hasButtonWithText(page, 'Create New Character'), 'Has "Create New Character" button');
  assert(await hasButtonWithText(page, 'Clear Points Bought'), 'Has "Clear Points Bought" button');

  // ── Attribute modification changes points ─────────────────────────
  console.log('\nModifying attributes');
  const rows = await page.$$('.attribute-row');
  if (rows.length > 0) {
    const plusBtns = await rows[0].$$('button');
    for (const btn of plusBtns) {
      const t = await page.evaluate(el => el.textContent.trim(), btn);
      if (t === '+') { await btn.click(); await btn.click(); break; }
    }
  }
  await wait(300);
  const afterBump = await getBodyText(page);
  assert(!afterBump.includes('Points spent: 0 / 27'), 'Points change after increasing attribute');
});

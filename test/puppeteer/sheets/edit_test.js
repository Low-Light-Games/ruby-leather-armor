const {
  runSuite, setupPage, login,
  clickButtonByText, hasButtonWithText, getInputValue, wait, screenshot,
} = require('../support/helpers');

/**
 * Pre-condition: a character named "Test Hero" must exist
 *   (run create_test.js first, or seed one).
 */
runSuite('Sheets › Edit character', async (browser, assert) => {
  const page = await setupPage(browser, { acceptDialogs: true });
  await login(page, 'user');
  await wait(2000); // wait for sheet list to load

  // ── Click Edit on "Test Hero" ─────────────────────────────────────
  console.log('Click Edit for "Test Hero"');
  const items = await page.$$('.sheet-list-item');
  let editClicked = false;
  for (const item of items) {
    const txt = await page.evaluate(el => el.innerText, item);
    if (txt.includes('Test Hero')) {
      const btn = await item.$('.edit-button');
      if (btn) { await btn.click(); editClicked = true; }
      break;
    }
  }
  assert(editClicked, 'Edit button clicked for "Test Hero"');
  await wait(1000);

  // ── Fields populated ──────────────────────────────────────────────
  console.log('\nFields populated');
  const nameVal = await page.evaluate(() => {
    const el = document.querySelector('input[type="text"]');
    return el ? el.value : '';
  });
  assert(nameVal === 'Test Hero', 'Name populated with "Test Hero"');

  const descVal = await getInputValue(page, '#character-description');
  assert(descVal === 'A brave test warrior', 'Description populated');

  assert(await hasButtonWithText(page, 'Update Sheet'), 'Button says "Update Sheet"');

  await screenshot(page, 'sheet_editing');
});

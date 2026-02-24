const {
  runSuite, setupPage, login,
  getBodyText, clickButtonByText, hasButtonWithText, getInputValue, wait,
} = require('../support/helpers');

/**
 * Pre-condition: a character named "Test Hero" must exist.
 */
runSuite('Sheets › Clear points & Create new', async (browser, assert) => {
  const page = await setupPage(browser, { acceptDialogs: true });
  await login(page, 'user');
  await wait(2000);

  // Load "Test Hero" into editor
  const items = await page.$$('.sheet-list-item');
  for (const item of items) {
    const txt = await page.evaluate(el => el.innerText, item);
    if (txt.includes('Test Hero')) {
      const btn = await item.$('.edit-button');
      if (btn) await btn.click();
      break;
    }
  }
  await wait(1000);

  // ── Clear Points ──────────────────────────────────────────────────
  console.log('Clear Points Bought');
  await clickButtonByText(page, 'Clear Points Bought');
  await wait(500);

  const afterClear = await getBodyText(page);
  assert(afterClear.includes('Points spent: 0 / 27'), 'Points reset to 0');

  // Name & description preserved
  const name = await page.evaluate(() => {
    const el = document.querySelector('input[type="text"]');
    return el ? el.value : '';
  });
  assert(name === 'Test Hero', 'Name preserved after clear');

  const desc = await getInputValue(page, '#character-description');
  assert(desc === 'A brave test warrior', 'Description preserved after clear');

  // ── Create New Character ──────────────────────────────────────────
  console.log('\nCreate New Character resets form');
  await clickButtonByText(page, 'Create New Character');
  await wait(1000);

  const nameAfter = await page.evaluate(() => {
    const el = document.querySelector('input[type="text"]');
    return el ? el.value : 'NOT_EMPTY';
  });
  assert(nameAfter === '', 'Name cleared');

  const descAfter = await getInputValue(page, '#character-description');
  assert(descAfter === '', 'Description cleared');

  assert(await hasButtonWithText(page, 'Save Sheet'), 'Button reverts to "Save Sheet"');
});

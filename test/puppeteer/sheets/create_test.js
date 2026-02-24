const {
  runSuite, setupPage, login,
  getBodyText, clickButtonByText, getTextContent, wait, screenshot,
} = require('../support/helpers');

runSuite('Sheets › Create character', async (browser, assert) => {
  const page = await setupPage(browser, { acceptDialogs: true });
  await login(page, 'user');

  // ── Fill out name & description ───────────────────────────────────
  console.log('Create a character sheet');
  const inputs = await page.$$('input[type="text"]');
  if (inputs.length > 0) {
    await inputs[0].click({ clickCount: 3 });
    await inputs[0].type('Test Hero');
  }

  const desc = await page.$('#character-description');
  if (desc) await desc.type('A brave test warrior');

  // Bump an attribute
  const rows = await page.$$('.attribute-row');
  if (rows.length > 0) {
    const btns = await rows[0].$$('button');
    for (const btn of btns) {
      const t = await page.evaluate(el => el.textContent.trim(), btn);
      if (t === '+') { await btn.click(); break; }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────
  const savePromise = page.waitForResponse(
    res => res.url().includes('/sheets') && res.request().method() === 'POST',
    { timeout: 10000 }
  ).catch(() => null);

  await clickButtonByText(page, 'Save Sheet');
  await savePromise;
  await wait(2000);

  const afterSave = await getBodyText(page);
  assert(
    afterSave.includes('Sheet saved successfully') || afterSave.includes('Test Hero'),
    'Sheet saved or character appears in list'
  );

  // ── Appears in list ───────────────────────────────────────────────
  console.log('\nCharacter in list');
  const listText = await getTextContent(page, '.sheet-list');
  assert(listText.includes('Test Hero'), '"Test Hero" appears in character list');

  const editBtns = await page.$$('.edit-button');
  assert(editBtns.length > 0, 'Edit button exists next to character');

  await screenshot(page, 'sheet_created');
});

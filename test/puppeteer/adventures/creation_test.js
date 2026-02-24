const {
  BASE_URL, runSuite, setupPage, login,
  getBodyText, hasButtonWithText, getTextContent,
  getSelectOptions, selectOptionByText, wait, screenshot,
} = require('../support/helpers');

/**
 * Pre-condition: at least one character sheet and the seeded
 * "The Lake of Whispers" story must exist.
 */
runSuite('Adventures › Creation form', async (browser, assert) => {
  const page = await setupPage(browser);
  await login(page, 'user');

  await page.goto(`${BASE_URL}/adventures/new`, { waitUntil: 'networkidle2', timeout: 15000 });
  await wait(2000);

  // ── Page loads ────────────────────────────────────────────────────
  console.log('Adventure creation page');
  const body = await getBodyText(page);
  assert(body.includes('Start a New Adventure'), 'Page title present');

  assert(await page.$('#sheet-select') !== null, 'Character select present');
  assert(await page.$('#story-select') !== null, 'Story select present');
  assert(await hasButtonWithText(page, 'Begin Adventure'), '"Begin Adventure" button present');

  // ── Dropdowns populated ───────────────────────────────────────────
  console.log('\nDropdowns populated');
  const storyOpts = await getSelectOptions(page, '#story-select');
  assert(storyOpts.some(o => o.text.includes('Lake of Whispers')), '"The Lake of Whispers" in story dropdown');

  const sheetOpts = await getSelectOptions(page, '#sheet-select');
  assert(sheetOpts.length > 1, 'At least one character in sheet dropdown'); // first is placeholder

  // ── Story preview ─────────────────────────────────────────────────
  console.log('\nStory preview');
  await selectOptionByText(page, '#story-select', 'Lake of Whispers');
  await wait(500);

  assert(await page.$('.story-preview') !== null, 'Story preview box appears');

  const previewText = await getTextContent(page, '.story-preview');
  assert(previewText.includes('village') && previewText.includes('kidnapped'), 'Preview text shown');
  assert(!previewText.includes('Aboleth'), 'Full premise NOT exposed');

  // ── Character preview ─────────────────────────────────────────────
  console.log('\nCharacter preview');
  // Select the first real character option
  const firstChar = sheetOpts.find(o => o.value !== '');
  if (firstChar) await page.select('#sheet-select', firstChar.value);
  await wait(500);

  assert(await page.$('.character-preview') !== null, 'Character preview box appears');
  const charText = await getTextContent(page, '.character-preview');
  assert(charText.length > 0, 'Character preview has content');

  await screenshot(page, 'adventure_creation');
});

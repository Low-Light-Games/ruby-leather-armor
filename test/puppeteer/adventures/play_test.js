const {
  BASE_URL, runSuite, setupPage, login,
  clickButtonByText, selectOptionByText, getTextContent, wait, screenshot,
} = require('../support/helpers');

/**
 * Pre-condition: at least one character sheet and the seeded
 * "The Lake of Whispers" story must exist.
 *
 * This test creates an adventure and then verifies the play page.
 */
runSuite('Adventures › Play page', async (browser, assert) => {
  const page = await setupPage(browser);
  await login(page, 'user');

  // ── Create an adventure first ─────────────────────────────────────
  console.log('Creating an adventure');
  await page.goto(`${BASE_URL}/adventures/new`, { waitUntil: 'networkidle2', timeout: 15000 });
  await wait(2000);

  await selectOptionByText(page, '#story-select', 'Lake of Whispers');
  // Pick the first available character
  const firstChar = await page.evaluate(() => {
    const sel = document.querySelector('#sheet-select');
    if (!sel) return '';
    for (const o of sel.options) { if (o.value) return o.value; }
    return '';
  });
  if (firstChar) await page.select('#sheet-select', firstChar);
  await wait(300);

  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 15000 }),
    clickButtonByText(page, 'Begin Adventure'),
  ]);
  await wait(2000);

  const url = page.url();
  assert(url.includes('/adventures/'), 'Redirected to adventure play page');

  // ── Play page layout ──────────────────────────────────────────────
  console.log('\nPlay page layout');
  assert(await page.$('.app-header') !== null, 'Navbar present');

  const columns = await page.$$('.adventure-column');
  assert(columns.length === 3, `Has 3 columns (found ${columns.length})`);

  // Character column
  console.log('\nCharacter column');
  assert(await page.$('.character-column') !== null, 'Character column present');
  const charText = await getTextContent(page, '.character-column');
  assert(charText.toLowerCase().includes('strength'), 'Shows attributes');
  assert(charText.toLowerCase().includes('gold'), 'Shows gold');

  // Story column
  console.log('\nStory column');
  assert(await page.$('.story-column') !== null, 'Story column present');
  const storyText = await getTextContent(page, '.story-column');
  assert(storyText.includes('Lake of Whispers'), 'Shows story title');
  assert(storyText.includes('hero'), 'Shows current stage description');

  // Middle column
  assert(await page.$('.middle-column') !== null, 'Middle column present');

  await screenshot(page, 'adventure_play');
});

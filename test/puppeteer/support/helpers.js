const puppeteer = require('puppeteer');

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

const CREDENTIALS = {
  admin: { email: 'admin@example.com', password: 'admin123' },
  user:  { email: 'test@example.com',  password: 'test123' },
};

// ── Assertion tracker ───────────────────────────────────────────────
function createTracker() {
  const state = { passed: 0, failed: 0, failures: [] };

  function assert(condition, message) {
    if (condition) {
      console.log(`  ✅ ${message}`);
      state.passed++;
    } else {
      console.error(`  ❌ ${message}`);
      state.failures.push(message);
      state.failed++;
    }
  }

  function summary() {
    console.log(`\n${'─'.repeat(50)}`);
    console.log(`Results: ${state.passed} passed, ${state.failed} failed`);
    if (state.failures.length > 0) {
      console.log(`\nFailed assertions:`);
      state.failures.forEach(f => console.log(`  - ${f}`));
    }
    console.log(`${'─'.repeat(50)}\n`);
    return state.failed;
  }

  return { assert, summary, state };
}

// ── Browser helpers ─────────────────────────────────────────────────
async function launchBrowser() {
  return puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
    ],
  });
}

async function setupPage(browser, { acceptDialogs = false } = {}) {
  const page = await browser.newPage();
  page.on('pageerror', error => console.log('  [PAGE ERROR]', error.message));
  if (acceptDialogs) {
    page.on('dialog', async dialog => await dialog.accept());
  }
  return page;
}

// ── Navigation & Auth helpers ───────────────────────────────────────
async function login(page, role = 'user') {
  const { email, password } = CREDENTIALS[role];
  await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 15000 });

  const hasEmailInput = await page.$('input[type="email"]');
  if (!hasEmailInput) return; // already logged in

  await page.type('input[type="email"]', email);
  await page.type('input[type="password"]', password);
  await Promise.all([
    page.waitForResponse(res => res.url().includes('login'), { timeout: 10000 }),
    page.click('button[type="submit"]'),
  ]);
  await wait(2000);
}

async function logout(page) {
  const clicked = await clickButtonByText(page, 'Logout');
  await wait(2000);
  return clicked;
}

// ── DOM helpers ─────────────────────────────────────────────────────
async function getBodyText(page) {
  return page.evaluate(() => document.body.innerText);
}

async function clickButtonByText(page, text) {
  const buttons = await page.$$('button');
  for (const btn of buttons) {
    const btnText = await page.evaluate(el => el.textContent, btn);
    if (btnText.trim().toLowerCase().includes(text.toLowerCase())) {
      await btn.click();
      return true;
    }
  }
  return false;
}

async function hasButtonWithText(page, text) {
  return page.evaluate((t) => {
    const buttons = [...document.querySelectorAll('button')];
    return buttons.some(b => b.textContent.includes(t));
  }, text);
}

async function getSelectOptions(page, selector) {
  return page.evaluate((sel) => {
    const select = document.querySelector(sel);
    if (!select) return [];
    return [...select.options].map(o => ({ value: o.value, text: o.text }));
  }, selector);
}

async function selectOptionByText(page, selector, text) {
  const value = await page.evaluate((sel, t) => {
    const select = document.querySelector(sel);
    if (!select) return '';
    for (const option of select.options) {
      if (option.text.includes(t)) return option.value;
    }
    return '';
  }, selector, text);

  if (value) await page.select(selector, value);
  return value;
}

async function getInputValue(page, selector) {
  return page.evaluate((sel) => {
    const el = document.querySelector(sel);
    return el ? el.value : null;
  }, selector);
}

async function getTextContent(page, selector) {
  return page.evaluate((sel) => {
    const el = document.querySelector(sel);
    return el ? el.innerText : '';
  }, selector);
}

function wait(ms) {
  return new Promise(r => setTimeout(r, ms));
}

async function screenshot(page, name) {
  await page.screenshot({
    path: `test/puppeteer/screenshots/${name}.png`,
    fullPage: true,
  }).catch(() => {});
}

// ── Test runner wrapper ─────────────────────────────────────────────
async function runSuite(name, fn) {
  const tracker = createTracker();

  console.log(`\n${'═'.repeat(50)}`);
  console.log(`  ${name}`);
  console.log(`${'═'.repeat(50)}`);
  console.log(`Target: ${BASE_URL}\n`);

  const browser = await launchBrowser();

  try {
    await fn(browser, tracker.assert);
  } catch (error) {
    console.error(`\n💥 UNEXPECTED ERROR: ${error.message}`);
    tracker.state.failed++;
  } finally {
    await browser.close();
  }

  const failures = tracker.summary();
  if (failures > 0) process.exit(1);
}

module.exports = {
  BASE_URL,
  CREDENTIALS,
  createTracker,
  launchBrowser,
  setupPage,
  login,
  logout,
  getBodyText,
  clickButtonByText,
  hasButtonWithText,
  getSelectOptions,
  selectOptionByText,
  getInputValue,
  getTextContent,
  wait,
  screenshot,
  runSuite,
};

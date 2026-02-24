const puppeteer = require('puppeteer');

// Inside the Docker container, the Rails app is at localhost:3000
const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';
const ADMIN_EMAIL = 'admin@example.com';
const ADMIN_PASSWORD = 'admin123';
const TEST_EMAIL = 'test@example.com';
const TEST_PASSWORD = 'test123';

let passed = 0;
let failed = 0;
const failures = [];

function assert(condition, message) {
  if (condition) {
    console.log(`  ✅ ${message}`);
    passed++;
  } else {
    console.error(`  ❌ ${message}`);
    failures.push(message);
    failed++;
  }
}

async function testAuthFlow() {
  console.log(`\nPuppeteer Auth Flow Tests`);
  console.log(`Target: ${BASE_URL}\n`);

  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
    ],
  });

  const page = await browser.newPage();

  // Capture console and errors for debugging
  page.on('pageerror', error => console.log('  [PAGE ERROR]', error.message));

  try {
    // ── Test 1: Unauthenticated user sees login form ──────────────────
    console.log('Test 1: Unauthenticated user sees login form');
    await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 15000 });

    const hasEmailInput = await page.$('input[type="email"]') !== null;
    const hasPasswordInput = await page.$('input[type="password"]') !== null;
    const hasSubmitButton = await page.$('button[type="submit"]') !== null;

    assert(hasEmailInput, 'Login form has email input');
    assert(hasPasswordInput, 'Login form has password input');
    assert(hasSubmitButton, 'Login form has submit button');

    // ── Test 2: Login with invalid credentials shows error ────────────
    console.log('\nTest 2: Login with invalid credentials shows error');
    await page.type('input[type="email"]', 'wrong@example.com');
    await page.type('input[type="password"]', 'wrongpassword');
    await page.click('button[type="submit"]');
    await new Promise(r => setTimeout(r, 2000));

    const pageText = await page.evaluate(() => document.body.innerText);
    const hasError = pageText.toLowerCase().includes('invalid') ||
                     pageText.toLowerCase().includes('failed') ||
                     pageText.toLowerCase().includes('error');
    assert(hasError, 'Error message shown for invalid credentials');

    // Clear inputs for next test
    await page.$eval('input[type="email"]', el => el.value = '');
    await page.$eval('input[type="password"]', el => el.value = '');

    // ── Test 3: Login with valid admin credentials ────────────────────
    console.log('\nTest 3: Login with valid admin credentials');
    await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 15000 });

    await page.type('input[type="email"]', ADMIN_EMAIL);
    await page.type('input[type="password"]', ADMIN_PASSWORD);

    // Verify CSRF token is present
    const csrfToken = await page.$eval(
      'meta[name="csrf-token"]',
      el => el.getAttribute('content')
    ).catch(() => null);
    assert(csrfToken !== null && csrfToken.length > 0, 'CSRF token is present in meta tag');

    // Submit and wait for response
    await Promise.all([
      page.waitForResponse(
        res => res.url().includes('login'),
        { timeout: 10000 }
      ),
      page.click('button[type="submit"]'),
    ]);
    await new Promise(r => setTimeout(r, 2000));

    // Should see authenticated UI
    const bodyAfterLogin = await page.evaluate(() => document.body.innerText);
    const isLoggedIn = bodyAfterLogin.includes('Logged in as') ||
                       bodyAfterLogin.includes(ADMIN_EMAIL) ||
                       bodyAfterLogin.includes('admin@example.com');
    assert(isLoggedIn, 'Admin user is logged in');

    const noLoginForm = await page.$('input[type="email"]') === null;
    assert(noLoginForm, 'Login form is no longer visible');

    // ── Test 4: Admin can see admin view ──────────────────────────────
    console.log('\nTest 4: Admin user sees admin view');
    const hasAdminView = bodyAfterLogin.toLowerCase().includes('admin') ||
                         bodyAfterLogin.toLowerCase().includes('all character sheets') ||
                         bodyAfterLogin.toLowerCase().includes('all sheets');
    assert(hasAdminView, 'Admin view/section is visible');

    // ── Test 5: Logout ────────────────────────────────────────────────
    console.log('\nTest 5: Logout');
    const logoutButton = await page.$('button');
    const buttons = await page.$$('button');
    let logoutClicked = false;
    for (const btn of buttons) {
      const text = await page.evaluate(el => el.textContent, btn);
      if (text.toLowerCase().includes('logout') || text.toLowerCase().includes('log out')) {
        await btn.click();
        logoutClicked = true;
        break;
      }
    }
    assert(logoutClicked, 'Logout button found and clicked');

    await new Promise(r => setTimeout(r, 2000));

    const hasLoginAfterLogout = await page.$('input[type="email"]') !== null;
    assert(hasLoginAfterLogout, 'Login form reappears after logout');

    // ── Test 6: Login as regular user (no admin view) ─────────────────
    console.log('\nTest 6: Regular user has no admin view');
    await page.type('input[type="email"]', TEST_EMAIL);
    await page.type('input[type="password"]', TEST_PASSWORD);
    await Promise.all([
      page.waitForResponse(
        res => res.url().includes('login'),
        { timeout: 10000 }
      ),
      page.click('button[type="submit"]'),
    ]);
    await new Promise(r => setTimeout(r, 2000));

    const regularBody = await page.evaluate(() => document.body.innerText);
    const regularLoggedIn = regularBody.includes('test@example.com') ||
                            regularBody.includes('Logged in as');
    assert(regularLoggedIn, 'Regular user is logged in');

    const noAdminSection = !regularBody.toLowerCase().includes('all character sheets');
    assert(noAdminSection, 'Regular user does not see admin "All Character Sheets" section');

    // Take a final screenshot
    await page.screenshot({ path: 'test/puppeteer/final_state.png', fullPage: true });

  } catch (error) {
    console.error(`\n💥 UNEXPECTED ERROR: ${error.message}`);
    await page.screenshot({ path: 'test/puppeteer/error_screenshot.png', fullPage: true }).catch(() => {});
    failed++;
  } finally {
    await browser.close();
  }

  // ── Summary ───────────────────────────────────────────────────────
  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Results: ${passed} passed, ${failed} failed`);
  if (failures.length > 0) {
    console.log(`\nFailed assertions:`);
    failures.forEach(f => console.log(`  - ${f}`));
  }
  console.log(`${'─'.repeat(50)}\n`);

  if (failed > 0) {
    process.exit(1);
  }
}

testAuthFlow();

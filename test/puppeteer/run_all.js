const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

/**
 * Discovers and runs all *_test.js files under test/puppeteer/,
 * skipping the support/ directory. Runs them sequentially so
 * tests that depend on prior state (e.g. sheet creation before
 * sheet editing) execute in the right order.
 *
 * Directory order: auth → sheets → navbar → adventures
 * (alphabetical within each directory).
 */
const SUITE_ORDER = ['auth', 'navbar', 'sheets', 'adventures'];
const ROOT = __dirname;

function discoverTests() {
  const tests = [];

  for (const dir of SUITE_ORDER) {
    const dirPath = path.join(ROOT, dir);
    if (!fs.existsSync(dirPath)) continue;

    const files = fs.readdirSync(dirPath)
      .filter(f => f.endsWith('_test.js'))
      .sort();

    for (const file of files) {
      tests.push(path.join(dirPath, file));
    }
  }

  return tests;
}

async function main() {
  const tests = discoverTests();

  console.log(`\n${'═'.repeat(50)}`);
  console.log(`  Puppeteer Test Runner`);
  console.log(`  Found ${tests.length} test suites`);
  console.log(`${'═'.repeat(50)}\n`);

  // Ensure screenshots directory exists
  const screenshotsDir = path.join(ROOT, 'screenshots');
  if (!fs.existsSync(screenshotsDir)) {
    fs.mkdirSync(screenshotsDir, { recursive: true });
  }

  let totalPassed = 0;
  let totalFailed = 0;
  const failedSuites = [];

  for (const testFile of tests) {
    const relative = path.relative(ROOT, testFile);
    console.log(`\n▶ Running: ${relative}`);

    try {
      execSync(`node "${testFile}"`, {
        stdio: 'inherit',
        env: { ...process.env },
      });
      totalPassed++;
    } catch (err) {
      totalFailed++;
      failedSuites.push(relative);
    }
  }

  console.log(`\n${'═'.repeat(50)}`);
  console.log(`  Final Summary`);
  console.log(`  Suites: ${totalPassed} passed, ${totalFailed} failed (${tests.length} total)`);
  if (failedSuites.length > 0) {
    console.log(`\n  Failed suites:`);
    failedSuites.forEach(s => console.log(`    - ${s}`));
  }
  console.log(`${'═'.repeat(50)}\n`);

  if (totalFailed > 0) process.exit(1);
}

main();

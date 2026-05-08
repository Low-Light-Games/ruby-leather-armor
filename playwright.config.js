const { defineConfig, devices } = require('@playwright/test');

// Tests target the e2e Docker stack defined in compose.e2e.yml (host port 3100).
// Bring it up before running tests:  docker compose -f compose.e2e.yml up -d --build
// Override target with BASE_URL=http://... to point elsewhere.
// Timeouts are sized for live OpenAI calls. A single player turn can chain
// several real model round-trips through the evaluator fan-out; per-action
// expectations need wider room than a stubbed run would.
module.exports = defineConfig({
  testDir: 'test/e2e',
  timeout: 180_000,
  expect: { timeout: 30_000 },
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3100',
    headless: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});

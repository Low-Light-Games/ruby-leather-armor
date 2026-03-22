// @ts-check
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: 'test/e2e',
  timeout: 30_000,
  expect: { timeout: 8_000 },
  reporter: 'list',

  // Playwright starts the Rails server before running tests and shuts it down
  // after. Set BASE_URL to skip this and point at an already-running server.
  webServer: process.env.BASE_URL ? undefined : {
    command: 'rm -f tmp/pids/server.pid && STUB_OPENAI=true bundle exec rails server -p 3000 -b 0.0.0.0',
    url: 'http://localhost:3000/up',
    reuseExistingServer: true,
    timeout: 30_000,
    stdout: 'ignore',
    stderr: 'pipe',
  },

  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    headless: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});

const { defineConfig, devices } = require('@playwright/test');

// Two run modes:
//
//   1. Docker compose stack — `docker compose -f compose.e2e.yml run --rm
//      playwright`. The playwright service sets BASE_URL=http://app:3000,
//      so the `webServer` branch below is skipped. Used for local headless
//      runs and the recommended path for iterating.
//
//   2. Host-native — `npx playwright test` with no BASE_URL. The webServer
//      branch boots Rails on :3000 itself; relies on the surrounding
//      environment (CI workflow `env:` block, or your local shell) to
//      provide DATABASE_URL, OPENAI_API_KEY, EVALUATOR_URL, etc. This is
//      how the GitHub Actions e2e job runs — postgres + evaluator are
//      stood up beforehand and Playwright handles Rails.
//
// Set BASE_URL=http://localhost:3100 if you want a host-side run targeting
// a docker stack that's already up.
//
// Timeouts are sized for live OpenAI calls. A single player turn can chain
// several real model round-trips through the evaluator fan-out; per-action
// expectations need wider room than a stubbed run would.
module.exports = defineConfig({
  testDir: 'test/e2e',
  timeout: 180_000,
  expect: { timeout: 30_000 },
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  webServer: process.env.BASE_URL ? undefined : {
    command: 'rm -f tmp/pids/server.pid && RAILS_ENV=playwright bundle exec rails server -p 3000 -b 0.0.0.0',
    url: 'http://localhost:3000/up',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    stdout: 'ignore',
    stderr: 'pipe',
  },
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    headless: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});

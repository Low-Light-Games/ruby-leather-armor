const { expect } = require('@playwright/test');

// `Math.floor(Math.random() * 20) + 1` is how the React side rolls d20s.
// Forcing `Math.random` to 0.999 makes every d20 land on 20 — used by
// every spec that needs predictable rolls. Page initScripts run on every
// navigation, so this survives `login` / `beginAdventure` redirects.
async function forceMaxRoll(page) {
  await page.addInitScript(() => { Math.random = () => 0.999; });
}

async function sendChatMessage(page, text) {
  const input = page.locator('.chat-input');
  await expect(input).toBeVisible({ timeout: 30_000 });
  await input.fill(text);
  await page.locator('.chat-send-btn').click();
}

module.exports = { forceMaxRoll, sendChatMessage };

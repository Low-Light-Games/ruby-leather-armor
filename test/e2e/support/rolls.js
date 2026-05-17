const { expect } = require('@playwright/test');

// All three pending-roll components render under .roll-submit-area:
//   - PendingRollsPanel: header "🎲 Rolls Needed", d20 button pops a result
//     dialog and gates Submit until the dialog is dismissed.
//   - PendingInitiativePanel: header "⚔️ Roll for Initiative!", d20 button
//     auto-submits.
//   - Either, with an unresolved skill: spinbutton + Submit Roll button,
//     no d20 button.
//
// `submitActiveRollPanel` handles all three. Resolves once the panel has
// disappeared from the DOM (signal the submit reached the server).

// @param  page  Playwright Page
// @param  options { typeMatch } — optional RegExp/string to constrain the
//                 panel by .roll-prompt-type label (e.g. /Swim/i).
async function submitActiveRollPanel(page, { typeMatch } = {}) {
  const panel = typeMatch
    ? page.locator('.roll-submit-area', {
        has: page.locator('.roll-prompt-type', { hasText: typeMatch }),
      })
    : page.locator('.roll-submit-area').first();
  await expect(panel).toBeVisible({ timeout: 180_000 });

  const d20Button = panel.locator('.roll-btn.roll-d20');
  if (await d20Button.count() > 0) {
    await d20Button.click();
    await dismissResultDialogIfPresent(page);
    await clickSubmitIfPresent(panel);
  } else {
    // Unresolved skill — manual entry, then Submit Roll.
    await panel.locator('input[type="number"], input[role="spinbutton"]').first().fill('20');
    await clickSubmitIfPresent(panel);
  }

  await expect(panel).toBeHidden({ timeout: 30_000 });
}

async function dismissResultDialogIfPresent(page) {
  const dialog = page.getByRole('dialog');
  if (!(await dialog.isVisible({ timeout: 2_000 }).catch(() => false))) return;

  await dialog.getByRole('button', { name: /close/i }).click();
  await dialog.waitFor({ state: 'hidden', timeout: 10_000 });
}

async function clickSubmitIfPresent(panel) {
  const submitBtn = panel.locator('.roll-submit-btn');
  if ((await submitBtn.count()) === 0) return; // PendingInitiativePanel auto-submits

  await expect(submitBtn).toBeEnabled({ timeout: 10_000 });
  await submitBtn.click();
}

module.exports = { submitActiveRollPanel };

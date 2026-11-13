// Visual regression: "did this screen change", not "does it match the design".
// Copy to <app>/e2e/visual.spec.ts and list the screens worth guarding.
//
// Baselines are only meaningful from the same OS and fonts every time. Create and update
// them in the Playwright container CI uses, never from a laptop:
//   docker run --rm -v "$PWD":/w -w /w mcr.microsoft.com/playwright:v<your version>-noble \
//     npx playwright test e2e/visual.spec.ts --update-snapshots
// A baseline update is a design decision — it goes in the PR for a human to look at.

import { expect, test, type Page } from '@playwright/test'

const SCREENS = [
  { name: 'settings', path: '/settings', ready: 'h1' },
]

async function stubData(page: Page) {
  // Fixed data, or every run differs. Replace with your API's fixtures.
  await page.route('**/api/**', (route) => route.fulfill({ json: [] }))
}

test.use({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 })

for (const screen of SCREENS) {
  test(`${screen.name} looks the same`, async ({ page }) => {
    await stubData(page)
    await page.goto(screen.path)
    await page.locator(screen.ready).first().waitFor()
    await page.evaluate(() => document.fonts.ready)
    await expect(page).toHaveScreenshot(`${screen.name}.png`, {
      fullPage: true,
      animations: 'disabled',
      mask: [page.locator('[data-visual="dynamic"]')],
      maxDiffPixelRatio: 0.01,
    })
  })
}
